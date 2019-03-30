# Copyright (C) 2019 MentalCollatz
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

import argparse
from base64 import b64encode
import os
import platform
import sys

from template import Script

DEFAULT_LISTEN_PORT = 17064

MAINNET_RPC_PORT = 14022
TESTNET_RPC_PORT = 18332

MAINNET_ADDR_FORMAT = {"bech32_hrp": "dgb", "prefix_pubkey": 30, "prefix_script": 63 }
TESTNET_ADDR_FORMAT = {"bech32_hrp": "dgbt", "prefix_pubkey": 126, "prefix_script": 140 }

def data_dir():
    if platform.system() == "Windows":
        return os.path.join(os.environ["APPDATA"], "DigiByte")
    elif platform.system() == "Darwin":
        return os.path.expanduser("~/Library/Application Support/DigiByte/")
    else:
        return os.path.expanduser("~/.digibyte/")

# base64 encode that works the same in both Python 2 and 3
def b64encode_helper(s):
    res = b64encode(s.encode())
    if type(res) == bytes:
        res = res.decode()
    return res

params = {}

def init(argv):
    parser = argparse.ArgumentParser(description="Solo-mining pool.")
    parser.add_argument("-t", "--testnet", help="use testnet params", action="store_true")
    parser.add_argument("-H", "--host", help="rpc host", dest="rpc_host", default="localhost")
    parser.add_argument("-p", "--port", help="rpc port", dest="rpc_port", type=int)
    parser.add_argument("--user", help="rpc user (discouraged, --auth is preferred)")
    parser.add_argument("--password", help="rpc password (discouraged, --auth is preferred)")
    parser.add_argument("-a", "--auth", help="rpc authorization file", type=argparse.FileType("r"))
    parser.add_argument("-l", "--listen", help="port to listen for miners on", dest="listen_port", default=DEFAULT_LISTEN_PORT, type=int)
    parser.add_argument("-r", "--remote", help="allow remote miners to connect", action="store_true")
    parser.add_argument("address", help="address to mine to", type=str)
    args = parser.parse_args(argv[1:])

    global params
    params = {key: getattr(args, key) for key in ["rpc_host", "listen_port", "testnet"]}
    
    addr_format = TESTNET_ADDR_FORMAT if args.testnet else MAINNET_ADDR_FORMAT
    cbscript = Script.from_address(args.address, **addr_format)
    if cbscript is None:
        other_addr_format = MAINNET_ADDR_FORMAT if args.testnet else TESTNET_ADDR_FORMAT
        cbscript = Script.from_address(args.address, **other_addr_format)
        if cbscript is not None:
            if args.testnet:
                parser.error("mainnet address specified with --testnet")
            else:
                parser.error("testnet address specified without --testnet")
        else:
            parser.error("invalid address")
    params["cbscript"] = cbscript.data
    
    if args.user and args.password:
        if args.auth:
            parser.error("argument --auth is not allowed with arguments --user and --password")
        if ':' in args.user:
            parser.error("user may not contain `:`")
        rpc_auth = args.user + ':' + args.password
    elif args.user or args.password:
        parser.error("--user and --password must both be present or neither present")
    elif args.auth:
        rpc_auth = args.auth.read()
    else:
        cookie = data_dir()
        if args.testnet:
            cookie = os.path.join(cookie, "testnet3")
        cookie = os.path.join(cookie, ".cookie")
        try:
            with open(cookie, "r") as f:
                # Note: if the user restarts the server, they will need to
                # restart the pool also
                rpc_auth = f.read()
        except IOError as e:
            parser.error("Unable to read default auth file `%s`, please specify auth file or user and password.")
    params["rpc_auth"] = "Basic " + b64encode_helper(rpc_auth)

    if args.rpc_port:
        rpc_port = args.rpc_port
    else:
        rpc_port = TESTNET_RPC_PORT if args.testnet else MAINNET_RPC_PORT
    params["rpc_port"] = rpc_port
    params["rpc_url"] = "http://%s:%d" % (params["rpc_host"], params["rpc_port"])

    params["bind_addr"] = "" if args.remote else "localhost"

def get(key):
    global params
    if not params:
        init(sys.argv)
    return params[key]
