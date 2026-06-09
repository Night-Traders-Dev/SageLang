# lib/blockchain/rpc.sage
# JSON-RPC 2.0 Server for SageChain

import net.server as server
import json

class RPCServer:
    proc init(blockchain, port):
        self.blockchain = blockchain
        self.port = port
        self.server = server.create_server("0.0.0.0", port)
        server.post_route(self.server["router"], "/rpc", self.handle_rpc)

    proc start():
        print "Starting JSON-RPC Server on port " + str(self.port)
        server.listen_and_serve(self.server)

    proc handle_rpc(req):
        if req["method"] != "POST":
            return server.response_error(405, "Method Not Allowed")

        let body = req["body"]
        let j_req = json.parse(body)
        
        if j_req == nil or not dict_has(j_req, "jsonrpc") or j_req["jsonrpc"] != "2.0":
            return self.send_rpc_error(-32600, "Invalid Request", nil)

        let method = j_req["method"]
        let params = []
        if dict_has(j_req, "params"):
            params = j_req["params"]
        let id = nil
        if dict_has(j_req, "id"):
            id = j_req["id"]
        
        let result = nil
        
        if method == "eth_blockNumber":
            result = len(self.blockchain.chain) - 1
        elif method == "eth_getBalance":
            result = self.blockchain.get_balance(params[0])
        elif method == "eth_getBlockByNumber":
            result = self.blockchain.get_block_by_height(params[0])
        elif method == "eth_getBlockByHash":
            result = self.blockchain.get_block_by_hash(params[0])
        elif method == "eth_getTransactionByHash":
            result = self.blockchain.get_transaction_by_hash(params[0])
        elif method == "eth_sendRawTransaction":
            let ok = self.blockchain.add_signed_transaction(params[0])
            result = ok
        elif method == "eth_gasPrice":
            result = 100
        elif method == "eth_chainId":
            result = 1
        else:
            return self.send_rpc_error(-32601, "Method not found", id)

        return self.send_rpc_result(result, id)

    proc send_rpc_result(result, id):
        let response = {
            "jsonrpc": "2.0",
            "result": result,
            "id": id
        }
        return server.response_json(json_stringify(response))

    proc send_rpc_error(code, message, id):
        let response = {
            "jsonrpc": "2.0",
            "error": {"code": code, "message": message},
            "id": id
        }
        return server.response_json(json_stringify(response))

proc json_stringify(value):
    let cjson = json.cJSON_FromSage(value)
    let str = json.cJSON_PrintUnformatted(cjson)
    json.cJSON_Delete(cjson)
    return str
