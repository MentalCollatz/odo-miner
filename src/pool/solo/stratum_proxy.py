#!/usr/bin/env python
# Forked from https://gist.github.com/fiorix/1878983

import sys
import json
import re
import random

import template

from twisted.internet import defer
from twisted.internet import protocol
from twisted.internet import reactor
from twisted.python import log

from binascii import hexlify, unhexlify

clicounter = 0

def toJson(obj):
    return json.dumps(obj).encode("utf-8")

def fromJson(str):
    return json.loads(str.decode('utf-8'))

class ProxyClientProtocol(protocol.Protocol):
    def connectionMade(self):
        global clicounter
        log.msg("Client: connected to peer")
        self.client_id = clicounter
        clicounter += 1
        self.cli_nonce2 = 0
        self.cli_queue = self.factory.cli_queue
        self.cli_queue.get().addCallback(self.serverDataReceived)

    def serverDataReceived(self, chunk):
        if chunk is False:
            self.cli_queue = None
            log.msg("Client: disconnecting from peer")
            self.factory.continueTrying = False
            self.transport.loseConnection()
        elif self.cli_queue:
            log.msg("Client: writing %d bytes to peer" % len(chunk))
            self.transport.write(chunk)
            self.cli_queue.get().addCallback(self.serverDataReceived)
        else:
            self.factory.cli_queue.put(chunk)

    def dataReceived(self, chunk):
        log.msg("Client: %d bytes received from peer" % len(chunk))
        curstr = chunk.splitlines()
        disconnectflag = False
        for val in curstr:
            try:
                data = fromJson(val)
                if data.has_key('method'):
                    if data.get('method') == 'mining.set_difficulty':
                        self.cli_diff = int(data.get('params')[0])
                        modifiedchunk = "set_target 000000000000000 (diff = %d)" % self.cli_diff
                    elif data.get('method') == 'mining.notify':
                        self.cli_wbclean = data.get('params')[8]
                        if self.cli_wbclean:
                            self.cli_nonce2 = random.randint(0,99999999)
                        else:
                            self.cli_nonce2 += 1
                        p_header = template.get_params_header(data.get('params'), self.cli_enonce1, self.cli_nonce2, self.cli_nonce2len)
                        self.cli_idstring = str(data.get('params')[0])
                        self.cli_time     = str(data.get('params')[7])
                        self.cli_target   = str(data.get('params')[9])
                        self.cli_odokey   = int(data.get('params')[10])
                        self.cli_target   = '00000000ffff0000000000000000000000000000000000000000000000000000'
                        modifiedchunk = "work %s %s %d %s %s %d" % (p_header, self.cli_target, self.cli_odokey, self.cli_idstring, self.cli_time, self.cli_nonce2)
                    else:
                        modifiedchunk = val   # send unmodified content
                elif data.has_key('reject-reason'):
                         modifiedchunk = "result rejected %s" % str(data.get('reject-reason'))
                elif data.has_key('result'):
                    if data.get('result') == True:
                         modifiedchunk = "result accepted"
                    elif data.get('id') == 0:
                         self.cli_enonce1 = str(data.get('result')[1])
                         self.cli_nonce2len = int(data.get('result')[2])
                         modifiedchunk = "set_subscribe_params %s %d" % (self.cli_enonce1, self.cli_nonce2len)
                    else:
                        modifiedchunk = val

                self.factory.srv_queue.put(modifiedchunk+'\n')    # send processed input
            except Exception as e:
                print(e)
                disconnectflag = True    # we do not want process non-JSON messages, set flag to disconnect
                break    # end for loop if any non-JSON line happen
        if disconnectflag:
            log.msg("Client: disconnect because JSON decode error: %s" % chunk)
            self.factory.continueTrying = False
            self.transport.loseConnection()

    def connectionLost(self, why):
        if self.cli_queue:
            self.cli_queue = None
            log.msg("Client: peer disconnected unexpectedly")


class ProxyClientFactory(protocol.ReconnectingClientFactory):
    maxDelay = 10
    continueTrying = True
    protocol = ProxyClientProtocol

    def __init__(self, srv_queue, cli_queue):
        self.srv_queue = srv_queue
        self.cli_queue = cli_queue

class ProxyServer(protocol.Protocol):
    def connectionMade(self):
        self.srv_queue = defer.DeferredQueue()
        self.cli_queue = defer.DeferredQueue()
        self.srv_queue.get().addCallback(self.clientDataReceived)

        factory = ProxyClientFactory(self.srv_queue, self.cli_queue)
        log.msg("Stratum: connect to %s:%s" % (self.stratumHost, self.stratumPort))
        reactor.connectTCP(self.stratumHost, self.stratumPort, factory)

    def clientDataReceived(self, chunk):
        log.msg("Server: writing %d bytes to original client" % len(chunk))
        self.transport.write(chunk)
        self.srv_queue.get().addCallback(self.clientDataReceived)

    def dataReceived(self, chunk):
        log.msg("Server: %d bytes received" % len(chunk))
        try:
            if re.match(r'subscribe', chunk):
                modifiedchunk = toJson({'id':0, 'method':'mining.subscribe','params':["odominer"]})
            elif re.match(r'auth', chunk):
                match_obj = re.match(r'auth\s(\w+)\s(\w+)', chunk)
                params = match_obj.group(1,2)
                self.cli_authid = match_obj.group(1)
                modifiedchunk = toJson({'id':1, 'method':'mining.authorize','params':params})
            elif re.match(r'submit_nonce', chunk):
                match_obj = re.match(r'submit_nonce\s(\w+)\s(\w+)\s(\w+)\s(\d+)', chunk)
                nonce2str = hexlify(template.serialize_int(int(match_obj.group(4))))
                nonce2hex = '0'* (8-len(nonce2str)) + nonce2str
                params = [self.cli_authid, str(match_obj.group(2)), nonce2hex, str(match_obj.group(3)), str(match_obj.group(1))]
                modifiedchunk = toJson({'id':0, 'method':'mining.submit','params':params})
            else:
                modifiedchunk = chunk   # send unmodified content
            self.cli_queue.put(modifiedchunk+'\n')    # send processed input
        except Exception as e:
            print(e)
            log.msg("Server: unknown data from client %s" % chunk)

    def connectionLost(self, why):
        self.cli_queue.put(False)

if __name__ == "__main__":

    from argparse import ArgumentParser
    usage = "%prog <stratum tcp host> <stratum tcp port> [options]"
    parser = ArgumentParser(description=usage)

    parser.add_argument("pool_host", metavar="host", help="stratum tcp host")
    parser.add_argument("pool_port", metavar="stratum_port", help="stratum tcp port", type=int, choices=range(1,65535))

    arguments = vars(parser.parse_args())
    log.startLogging(sys.stdout)

    ProxyServer.stratumHost = arguments["pool_host"]
    ProxyServer.stratumPort = arguments["pool_port"]

    log.startLogging(sys.stdout)
    factory = protocol.Factory()
    factory.protocol = ProxyServer
    reactor.listenTCP(9999, factory, interface="0.0.0.0")
    reactor.run()
