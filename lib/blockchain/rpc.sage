# lib/blockchain/rpc.sage
# JSON-RPC 2.0 Server for SageChain

import net.server as server
import json
import clock

class RPCServer:
    proc init(blockchain, port):
        self.blockchain = blockchain
        self.port = port
        self.server = server.new_server(port)
        self.setup_handlers()

    proc setup_handlers():
        server.handle(self.server, "/rpc", self.handle_rpc)

    proc start():
        print "Starting JSON-RPC Server on port " + str(self.port)
        server.listen_and_serve(self.server)

    proc handle_rpc(req, res):
        if req.method != "POST":
            server.send_error(res, 405, "Method Not Allowed")
            return

        let body = req.body
        let j_req = json.parse(body)
        
        # Validate JSON-RPC 2.0
        if j_req["jsonrpc"] != "2.0":
            self.send_rpc_error(res, -32600, "Invalid Request", j_req["id"])
            return

        let method = j_req["method"]
        let params = j_req["params"]
        let id = j_req["id"]
        
        let result = nil
        
        if method == "eth_blockNumber":
            result = len(self.blockchain.chain) - 1
        elif method == "eth_getBalance":
            result = self.blockchain.get_balance(params[0])
        elif method == "eth_getBlockByNumber":
            result = self.blockchain.db.get_block_by_height(params[0])
        elif method == "eth_sendRawTransaction":
            # params[0] is signed tx dict
            let ok = self.blockchain.add_signed_transaction(params[0])
            result = ok
        elif method == "eth_gasPrice":
            result = 100 # Static placeholder for now
        else:
            self.send_rpc_error(res, -32601, "Method not found", id)
            return

        self.send_rpc_result(res, result, id)

    proc send_rpc_result(res, result, id):
        let response = {
            "jsonrpc": "2.0",
            "result": result,
            "id": id
        }
        server.send_json(res, response)

    proc send_rpc_error(res, code, message, id):
        let response = {
            "jsonrpc": "2.0",
            "error": {"code": code, "message": message},
            "id": id
        }
        server.send_json(res, response)
