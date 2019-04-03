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

import socket
import threading
import time

import config
import rpc
from template import BlockTemplate

def get_templates(callback):
    longpollid = None
    last_errno = None
    while True:
        try:
            template = rpc.get_block_template(longpollid)
            if "coinbaseaux" not in template:
                template["coinbaseaux"] = {}
            template["coinbaseaux"]["cbstring"] = config.get("cbstring")
            callback(template)
            longpollid = template["longpollid"]
            if last_errno != 0:
                print("%s: successfully acquired template" % time.asctime())
                last_errno = 0
        except (rpc.RpcError, socket.error) as e:
            if last_errno == 0:
                callback(None)
            if e.errno != last_errno:
                last_errno = e.errno
                print("%s: %s (errno %d)" % (time.asctime(), e.strerror, e.errno))
            time.sleep(1)

class Manager(threading.Thread):
    def __init__(self, cbscript):
        threading.Thread.__init__(self)
        self.cbscript = cbscript
        self.template = None
        self.extra_nonce = 0
        self.miners = []
        self.cond = threading.Condition()
    
    def add_miner(self, miner):
        with self.cond:
            self.miners.append(miner)
            self.cond.notify()
    
    def remove_miner(self, miner):
        with self.cond:
            self.miners.remove(miner)
    
    def push_template(self, template):
        with self.cond:
            if template is None:
                self.template = None
            else:
                self.template = BlockTemplate(template, self.cbscript)
            self.extra_nonce = 0
            for miner in self.miners:
                miner.next_refresh = 0
            self.cond.notify()
    
    def run(self):
        while True:
            with self.cond:
                now = time.time()
                next_refresh = now + 1000
                for miner in self.miners:
                    if miner.next_refresh < now:
                        miner.push_work(self.template, self.extra_nonce)
                        self.extra_nonce += 1
                    next_refresh = min(next_refresh, miner.next_refresh)
                wait_time = max(0, next_refresh - time.time())
                self.cond.wait(wait_time)

class Miner(threading.Thread):
    def __init__(self, conn, manager):
        threading.Thread.__init__(self)
        self.conn = conn
        self.manager = manager
        self.lock = threading.Lock()
        self.conn_lock = threading.Lock()
        self.work_items = []
        self.next_refresh = 0
        self.refresh_interval = 10
        manager.add_miner(self)
        self.start()

    def push_work(self, template, extra_nonce):
        if template is None:
            workstr = "work %s %s %d" % ("0"*64, "0"*64, 0)
        else:
            work = template.get_work(extra_nonce)
            workstr = "work %s %s %d" % (work, template.target, template.odo_key)
        with self.lock:
            if template is None:
                self.work_items = []
            else:
                self.work_items.insert(0, (work, template, extra_nonce))
                if len(self.work_items) > 2:
                    self.work_items.pop()
            self.next_refresh = time.time() + self.refresh_interval
        try:
            self.send(workstr)
        except socket.error as e:
            # let the other thread clean it up
            pass

    def send(self, s):
        with self.conn_lock:
            self.conn.sendall((s + "\n").encode())

    def submit(self, work):
        with self.lock:
            for work_item in self.work_items:
                if work_item[0][0:152] == work[0:152]:
                    template = work_item[1]
                    extra_nonce = work_item[2]
                    submit_data = work + template.get_data(extra_nonce)
                    break
            else:
                return "stale"
        try:
            return rpc.submit_work(submit_data)
        except (rpc.RpcError, socket.error) as e:
            print("failed to submit: %s (errno %d)" % (e.strerror, e.errno));
            return "error"

    def run(self):
        while True:
            try:
                data = self.conn.makefile().readline().rstrip()
                if not data:
                    break
                parts = data.split()
                command, args = parts[0], parts[1:]
                if command == "submit" and len(args) == 1:
                    result = self.submit(*args)
                    self.send("result %s" % result)
                else:
                    print("unknown command: %s" % data)
            except socket.error as e:
                break
        self.manager.remove_miner(self)
        self.conn.close()

if __name__ == "__main__":
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((config.get("bind_addr"), config.get("listen_port")))
    listener.listen(10)

    manager = Manager(config.get("cbscript"))
    manager.start()
    
    callback = lambda t: manager.push_template(t)
    threading.Thread(target=get_templates, args=(callback,)).start()

    while True:
        conn, addr = listener.accept()
        Miner(conn, manager)

