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

import requests
import json

import config

class RpcError(Exception):
    def __init__(self, **kwargs):
        self.strerror = kwargs["message"]
        self.errno = kwargs["code"]

def json_request(method, *params):
    jdata = {"method": method, "params": params}
    headers = {"Content-Type": "application/json", "Authorization": config.get("rpc_auth")}
    response = requests.post(config.get("rpc_url"), headers=headers, json=jdata)

    try:
        data = response.json()
    except ValueError as e:
        if response.status_code != requests.codes.ok:
            raise RpcError(code=response.status_code, message="HTTP status code")
        raise RpcError(code=500, message=str(e))

    if data["error"] is None:
        return data["result"]
    raise RpcError(**data["error"])

def get_block_template(longpollid):
    params = {"rules":["segwit"]}
    algo = "odo"
    if longpollid is not None:
        params["longpollid"] = longpollid
    return json_request("getblocktemplate", params, algo)

def submit_work(submit_data):
    return json_request("submitblock", submit_data) or "accepted"

