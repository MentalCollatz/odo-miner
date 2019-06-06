#!/usr/bin/env python

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

import sys
from binascii import hexlify, unhexlify
from hashlib import sha256
from struct import pack

sys.path.append("../solo/")  
from template import sha256d, merkle_root, merkle_branch, serialize_int

def swap_order(d, wsz=8, gsz=1 ):
    return "".join(["".join([m[i:i+gsz] for i in range(wsz-gsz,-gsz,-gsz)]) for m in [d[i:i+wsz] for i in range(0,len(d),wsz)]])

def odokey_from_ntime(curtime, testnet):
    if testnet:
        nOdoShapechangeInterval = 1*24*60*60     # 1 days, testnet
    else:
        nOdoShapechangeInterval = 10*24*60*60    # 10 days, mainnet
    ntime = int(curtime, 16)
    odokey  = ntime - ntime % nOdoShapechangeInterval
    return odokey

def get_params_header(params, enonce1, nonce2, nonce2len):
    idstring  = params[0]
    prevhash  = swap_order(params[1][::-1])
    coinbase1 = params[2]
    coinbase2 = params[3]
    merklearr = params[4]
    version   = int(params[5], 16)
    bits      = params[6]
    curtime   = int(params[7], 16)

    txids = [unhexlify(tx) for tx in merklearr]
    mbranch = merkle_branch(txids)

    nonce2hex = n2hex(nonce2, nonce2len)
    coinbasehex = coinbase1+enonce1+nonce2hex+coinbase2
    coinbasetxid = sha256d(unhexlify(coinbasehex))

    data = pack('<I', version)
    data += unhexlify(prevhash)[::-1]
    data += merkle_root(coinbasetxid, mbranch)
    data += pack('<I', curtime)
    data += unhexlify(bits)[::-1]
    data += b'\0\0\0\0' # nonce

    return str(hexlify(data))

def n2hex(nonce2, nonce2len):
    nonce2str = hexlify(serialize_int(nonce2))
    nonce2hex = '0'* ((nonce2len*2)-len(nonce2str)) + nonce2str
    return nonce2hex

def difficulty_to_hextarget(difficulty):
    assert difficulty >= 0
    if difficulty == 0: return 2**256-1
    target = min(int((0xffff0000 * 2**(256-64) + 1)/difficulty - 1 + 0.5), 2**256-1)
    targethex = hex(target).rstrip("L").lstrip("0x")
    targetstr = '0'* (64 - len(targethex)) + targethex
    return str(targetstr)
