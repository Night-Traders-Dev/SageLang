# lib/blockchain/net.sage
# P2P Networking Layer for Sage Blockchain (Phase 4)

import net
import thread
import json

class P2PNode:
    proc init(blockchain, port):
        self.blockchain = blockchain
        self.port = port
        self.peers = []
        self.mutex = thread.mutex()
        
    async proc start():
        print "Starting P2P Node on port " + str(self.port)
        await net.listen(self.port, self.handle_connection)

    async proc handle_connection(conn):
        while true:
            let msg_str = await net.read(conn)
            if msg_str == nil:
                break
            
            let msg = json.parse(msg_str)
            if msg["type"] == "new_block":
                print "Received new block via P2P"
                self.blockchain.add_block(msg["data"])
            elif msg["type"] == "new_tx":
                self.blockchain.add_signed_transaction(msg["data"])

    async proc broadcast(msg_type, data):
        thread.lock(self.mutex)
        let current_peers = self.peers
        thread.unlock(self.mutex)
        
        let msg = {"type": msg_type, "data": data}
        let msg_str = json.stringify(msg)
        
        for peer in current_peers:
            let conn = await net.connect(peer["host"], peer["port"])
            if conn:
                await net.write(conn, msg_str)
                net.close(conn)

    proc add_peer(host, port):
        thread.lock(self.mutex)
        push(self.peers, {"host": host, "port": port})
        thread.unlock(self.mutex)
