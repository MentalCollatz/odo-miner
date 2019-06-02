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

from base58 import b58decode_check
from binascii import hexlify, unhexlify
from hashlib import sha256
from segwit_addr import decode as segwit_decode
from struct import pack

def sha256d(data):
    return sha256(sha256(data).digest()).digest()

def byte_ord(b):
    if type(b) == int:
        return b
    return ord(b)

def as_str(b):
    if type(b) == bytes:
        return b.decode()
    return b

# Serialize an integer using VarInt encoding
def serialize_int(n):
    result = b''
    if n == 0:
        return result

    while n != 0:
        result += pack('<B', n & 0xff)
        n >>= 8

    if byte_ord(result[-1]) & 0x80:
        result += b'\0'
    return result

# Serialize the length of an object
def compact_size(n):
    if hasattr(n, '__len__'):
        n = len(n)
    if n < 253:
        return pack('<B', n)
    elif n <= 0xffff:
        return b'\xfd' + pack('<H', n)
    elif n <= 0xffffffff:
        return b'\xfe' + pack('<I', n)
    else:
        return b'\xff' + pack('<Q', n)

# Compute the merkle branch for a list of transaction hashes
def merkle_branch(hashes):
    res = []
    while hashes:
        res.append(hashes.pop(0))
        if len(hashes) % 2:
            hashes.append(hashes[-1])
        hashes = [sha256d(hashes[i] + hashes[i + 1]) for i in range(0, len(hashes), 2)]
    return res

# Compute the merkle root from the coinbase hash and merkle branch
def merkle_root(cbhash, branch):
    res = cbhash
    for h in branch:
        res = sha256d(res + h)
    return res

# Split the mining reward between multiple parties.  The allotments argument is
# a list of (script, share) pairs, where "share" is either a float indicating
# the ratio to be given, or None indicating that it is to receive the remainder.
# Exactly one script should have None as the share.
def rewards_for_miners(total, allotments):
    res = []
    remaining = total
    main_script = None
    for script, share in allotments:
        if share is not None:
            portion = min(int(share * total), remaining)
            if portion > 0:
                res.append((portion, script))
                remaining -= portion
        else:
            assert main_script is None, "Expect exactly one script with None"
            main_script = script
    assert main_script is not None, "Expect exactly one script with None"
    if remaining > 0:
        res = [(remaining, main_script)] + res
    return res

class Script:
    OP_0 = 0x00
    OP_PUSHDATA1 = 0x4c
    OP_1 = 0x51
    OP_EQUAL = 0x87
    OP_EQUALVERIFY = 0x88
    OP_DUP = 0x76
    OP_CHECKSIG = 0xac
    OP_HASH160 = 0xa9

    def __init__(self):
        self.data = b''

    def push_byte(self, b):
        assert 0 <= b <= 255
        self.data += pack('<B', b)
        return self
        
    def push_int(self, n, use_opcodes=True):
        assert n >= 0, "Negative integers not supported"
        if use_opcodes:
            if n == 0:
                return self.push_byte(self.OP_0)
            elif n <= 16:
                return self.push_byte(n + self.OP_1 - 1)
        return self.push_str(serialize_int(n))

    def push_bytes(self, s):
        assert len(s) < self.OP_PUSHDATA1, "Long strings not supported"
        self.push_byte(len(s))
        for b in s:
            self.push_byte(b)
        return self

    def push_str(self, s):
        assert len(s) < self.OP_PUSHDATA1, "Long strings not supported"
        self.push_byte(len(s))
        self.data += s
        return self

    @classmethod
    def from_address(self, addr, bech32_hrp, prefix_pubkey, prefix_script):
        # bech32 address
        witver, witprog = segwit_decode(bech32_hrp, addr)
        if witver is not None:
            return Script().push_int(witver).push_bytes(witprog)

        # legacy address
        try:
            addrbin = b58decode_check(addr)
        except ValueError as e:
            return None
        addr_prefix = byte_ord(addrbin[0])
        addrbin = addrbin[1:]
        if len(addrbin) != 20:
            return None

        # pubkey hash
        if addr_prefix == prefix_pubkey:
            return Script()\
                .push_byte(self.OP_DUP)\
                .push_byte(self.OP_HASH160)\
                .push_str(addrbin)\
                .push_byte(self.OP_EQUALVERIFY)\
                .push_byte(self.OP_CHECKSIG)

        # script hash
        if addr_prefix == prefix_script:
            return Script()\
                .push_byte(self.OP_HASH160)\
                .push_str(addrbin)\
                .push_byte(self.OP_EQUAL)

        return None

class Coinbase:
    def __init__(self, cbscript, template):
        self.height = template["height"]
        self.txout = rewards_for_miners(template["coinbasevalue"], cbscript)
        self.needs_witness = any(tx["txid"] != tx["hash"] for tx in template["transactions"])
        if self.needs_witness:
            self.txout.append((0, unhexlify(template["default_witness_commitment"])))
        self.coinbaseaux = template.get("coinbaseaux", {})

    def _data(self, extra_nonce, extended):
        if not self.needs_witness:
            extended = False

        script_sig = Script()\
            .push_int(self.height)\
            .push_int(extra_nonce, False)
        for aux in self.coinbaseaux.values():
            if aux:
                script_sig.push_str(aux.encode())
        assert len(script_sig.data) <= 100, "script-sig too long"

        data = b'\x01\0\0\0' # transaction version
        if extended:
            data += b'\0' # extended
            data += b'\x01' # flags
        data += b'\x01' # txin count
        data += b'\0' * 32 # prevout hash
        data += b'\xff' * 4 # prevout n
        data += compact_size(script_sig.data) + script_sig.data
        data += b'\xff' * 4 # sequence
        data += compact_size(self.txout)
        for value, script in self.txout:
            data += pack('<Q', value)
            data += compact_size(script) + script
        if extended:
            data += b'\x01' # witness stack size
            data += b'\x20' # witness length
            data += b'\0' * 32 # witness
        data += b'\0' * 4 # lock time
        return data

    def data(self, extra_nonce):
        return self._data(extra_nonce, True)

    def txid(self, extra_nonce):
        return sha256d(self._data(extra_nonce, False))

class BlockTemplate:
    def __init__(self, template, cbscript):
        self.version = template["version"]
        self.previous_block_hash = unhexlify(template["previousblockhash"])[::-1]
        txids = [unhexlify(tx["txid"])[::-1] for tx in template["transactions"]]
        self.merkle_branch = merkle_branch(txids)
        self.time = template["curtime"]
        self.bits = unhexlify(template["bits"])[::-1]
        self.coinbase = Coinbase(cbscript, template)
        self.txdata = "".join(tx["data"] for tx in template["transactions"])
        self.target = template["target"]
        self.odo_key = template["odokey"]
        self.tx_count = len(template["transactions"]) + 1

    def get_work(self, extra_nonce):
        data = pack('<I', self.version)
        data += self.previous_block_hash
        data += merkle_root(self.coinbase.txid(extra_nonce), self.merkle_branch)
        data += pack('<I', self.time)
        data += self.bits
        data += b'\0\0\0\0' # nonce
        return as_str(hexlify(data))

    def get_data(self, extra_nonce):
        cb = self.coinbase.data(extra_nonce)
        return as_str(hexlify(compact_size(self.tx_count) + cb)) + self.txdata
