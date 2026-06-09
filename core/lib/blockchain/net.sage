# lib/blockchain/net.sage
# P2P Networking Layer for Sage Blockchain

import net
import thread
import json

proc json_stringify(value):
    let cjson = json.cJSON_FromSage(value)
    let str = json.cJSON_PrintUnformatted(cjson)
    json.cJSON_Delete(cjson)
    return str

class P2PNode:
    proc init(blockchain, port):
        self.blockchain = blockchain
        self.port = port
        self.peers = []
        self.mutex = thread.mutex()
        
    proc start():
        print "Starting P2P Node on port " + str(self.port)
        # Sync with known peers on startup
        self.sync_with_peers()
        net.listen(self.port, self.handle_connection)

    proc handle_connection(conn):
        while true:
            let msg_str = net.read(conn)
            if msg_str == nil:
                break
            
            let msg = json.parse(msg_str)
            if msg["type"] == "new_block":
                self.blockchain.add_block(msg["data"])
            elif msg["type"] == "new_tx":
                self.blockchain.add_signed_transaction(msg["data"])
            elif msg["type"] == "get_blocks":
                # Peer requested blocks from a certain height
                self.handle_get_blocks(conn, msg["data"])
            elif msg["type"] == "get_peers":
                self.handle_get_peers(conn)

    proc sync_with_peers():
        thread.lock(self.mutex)
        let p_list = self.peers
        thread.unlock(self.mutex)
        
        for peer in p_list:
            print "Syncing with peer " + peer["host"] + ":" + str(peer["port"])
            let conn = net.connect(peer["host"], peer["port"])
            if conn:
                # Request blocks from our current height
                let current_height = len(self.blockchain.chain)
                let msg = {"type": "get_blocks", "data": {"from": current_height}}
                net.write(conn, json_stringify(msg))
                
                # Read response blocks
                let resp_str = net.read(conn)
                if resp_str:
                    let resp = json.parse(resp_str)
                    if resp["type"] == "blocks_delivery":
                        let blocks = resp["data"]
                        for b_dict in blocks:
                            self.blockchain.add_block(b_dict)
                net.close(conn)

    proc handle_get_blocks(conn, data):
        let from_height = data["from"]
        let blocks = []
        let i = from_height
        while i < len(self.blockchain.chain) and len(blocks) < 50:
            push(blocks, self.blockchain.chain[i].to_dict())
            i = i + 1
        
        let resp = {"type": "blocks_delivery", "data": blocks}
        net.write(conn, json_stringify(resp))

    proc broadcast(msg_type, data):
        thread.lock(self.mutex)
        let current_peers = self.peers
        thread.unlock(self.mutex)
        
        let msg = {"type": msg_type, "data": data}
        let msg_str = json_stringify(msg)
        
        for peer in current_peers:
            let conn = net.connect(peer["host"], peer["port"])
            if conn:
                net.write(conn, msg_str)
                net.close(conn)

    proc add_peer(host, port):
        thread.lock(self.mutex)
        # Check if already added
        let exists = false
        for p in self.peers:
            if p["host"] == host and p["port"] == port:
                exists = true
                break
        if not exists:
            push(self.peers, {"host": host, "port": port})
        thread.unlock(self.mutex)
