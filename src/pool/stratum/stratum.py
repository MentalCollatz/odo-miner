#!/usr/bin/env python

#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import sys
import json
import re
import random

import header

from twisted.internet import defer
from twisted.internet import protocol
from twisted.internet import reactor
from twisted.python import log

clicounter = 0
extra_nonce = 0
verbose = False

def toJson(obj):
    return json.dumps(obj).encode("utf-8")

def fromJson(str):
    return json.loads(str.decode('utf-8'))

class ProxyClientProtocol(protocol.Protocol):
    def connectionMade(self):
        global clicounter
        global verbose
        self.client_id = clicounter
        clicounter += 1
        log.msg("Client[%d]: connected to peer" % self.client_id)
        self.cli_queue = self.factory.cli_queue
        self.cli_queue.get().addCallback(self.serverDataReceived)
        # subscribe after connect
        subscribe = toJson({'id':0, 'method':'mining.subscribe','params':["odominer"]})
        self.cli_queue.put(subscribe+'\n')

    def serverDataReceived(self, chunk):
        if chunk is False:
            self.cli_queue = None
            log.msg("Client: disconnecting from peer")
            self.factory.continueTrying = False
            self.transport.loseConnection()
        elif self.cli_queue:
            if verbose:
                log.msg("Client: writing %d bytes to peer" % len(chunk))
            self.transport.write(chunk)
            self.cli_queue.get().addCallback(self.serverDataReceived)
        else:
            self.factory.cli_queue.put(chunk)


    def dataReceived(self, chunk):
        global extra_nonce
        global verbose
        if verbose:
            log.msg("Client: %d bytes received from peer" % len(chunk))
        curstr = chunk.splitlines()
        disconnectflag = False
        for val in curstr:
            try:
                data = fromJson(val)
                if data.has_key('method'):
                    if data.get('method') == 'mining.set_difficulty':
                        self.cli_diff   = int(data.get('params')[0])
                        log.msg("diff from stratum = %d" % self.cli_diff)
                        if self.cli_diff < 1:    # it should not be happen but anyway
                            self.cli_diff = 1
                        self.cli_target = header.difficulty_to_hextarget(self.cli_diff)
                        modifiedchunk   = "set_target %s diff %d" % (self.cli_target, self.cli_diff)
                    elif data.get('method') == 'mining.notify':
                        self.cli_wbclean = data.get('params')[8]
                        if self.cli_wbclean and extra_nonce > 0:
                            extra_nonce = 0
                        else:
                            extra_nonce += 1
                        p_header = header.get_params_header(data.get('params'), self.cli_enonce1, extra_nonce, self.cli_n2len)
                        self.cli_idstring = str(data.get('params')[0])
                        self.cli_time     = str(data.get('params')[7])
                        self.cli_odokey   = int(data.get('odokey'))
                        self.cli_nonce2   = header.n2hex(extra_nonce, self.cli_n2len)
                        modifiedchunk = "work %s %s %d %s %s %s" % (p_header, self.cli_target, self.cli_odokey, self.cli_idstring, self.cli_time, self.cli_nonce2)
                    else:
                        modifiedchunk = val   # send unmodified content
                elif data.has_key('reject-reason'):
                         if str(data.get('reject-reason')) == "Stale":
                             modifiedchunk = "result stale"
                         else:
                             modifiedchunk = "result inconclusive"
                elif data.has_key('result'):
                    if data.get('result') == True and data.get('id') == 1:
                         modifiedchunk = "authorized"
                    elif data.get('result') == True:
                         modifiedchunk = "result accepted"
                    elif data.get('id') == 0:
                         self.cli_enonce1 = str(data.get('result')[1])
                         self.cli_n2len = int(data.get('result')[2])
                         modifiedchunk = "set_subscribe_params %s %d" % (self.cli_enonce1, self.cli_n2len)
                    else:
                        modifiedchunk = val

                self.factory.srv_queue.put(modifiedchunk+'\n')    # send processed input
            except Exception as e:
                print(e)
                disconnectflag = True    # we do not want process non-JSON messages, set flag to disconnect
                break    # end for loop if any non-JSON line happen
        if disconnectflag:
            log.msg("Client: disconnect because JSON decode error: %s" % chunk)
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
    global verbose
    def connectionMade(self):
        self.srv_queue = defer.DeferredQueue()
        self.cli_queue = defer.DeferredQueue()
        self.srv_queue.get().addCallback(self.clientDataReceived)

        factory = ProxyClientFactory(self.srv_queue, self.cli_queue)
        log.msg("Stratum: connect to %s:%s" % (self.stratumHost, self.stratumPort))
        reactor.connectTCP(self.stratumHost, self.stratumPort, factory)

    def clientDataReceived(self, chunk):
        if verbose:
            log.msg("Server: writing %d bytes to original client" % len(chunk))
        self.transport.write(chunk)
        self.srv_queue.get().addCallback(self.clientDataReceived)

    def doAuth(self, chunk):
        match_obj = re.match(r'auth\s(\w+)\s(\w+)', chunk)
        params = match_obj.group(1,2)
        self.cli_authid = match_obj.group(1)
        modifiedchunk = toJson({'id':self.cli_rpcid, 'method':'mining.authorize','params':params})
        self.cli_rpcid += 1
        self.cli_auth = modifiedchunk
        return modifiedchunk

    def dataReceived(self, chunk):
        if verbose:
            log.msg("Server: %d bytes received" % len(chunk))
        try:
            if re.match(r'auth', chunk):
                self.cli_rpcid = 1
                modifiedchunk = self.doAuth(chunk)
            elif re.match(r'submit_nonce', chunk):
                match_obj = re.match(r'submit_nonce\s(\w+)\s(\w+)\s(\w+)\s(\w+)', chunk)
                params = [self.cli_authid, str(match_obj.group(2)), match_obj.group(4), str(match_obj.group(3)), str(match_obj.group(1))]
                modifiedchunk = toJson({'id':self.cli_rpcid, 'method':'mining.submit','params':params})
                self.cli_rpcid += 1
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

    parser.add_argument("pool_host", metavar="stratum_host", help="stratum tcp host")
    parser.add_argument("pool_port", metavar="stratum_port", help="stratum tcp port", type=int, choices=range(1,65535))
    parser.add_argument("-v", "--verbose", help="increase output verbosity", action="store_true")
    parser.add_argument("--listen", metavar="port", help="listen tcp port", type=int, choices=range(1,65535), default=17065)

    arguments = vars(parser.parse_args())
    log.startLogging(sys.stdout)

    ProxyServer.stratumHost = arguments["pool_host"]
    ProxyServer.stratumPort = arguments["pool_port"]
    verbose = arguments["verbose"]
    listen_port = arguments["listen"]

    log.startLogging(sys.stdout)
    factory = protocol.Factory()
    factory.protocol = ProxyServer
    reactor.listenTCP(listen_port, factory, interface="0.0.0.0")
    reactor.run()