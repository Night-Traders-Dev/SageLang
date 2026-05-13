import net.server as server
import blockchain.db as db_mod
import json
import io

let db_path = "./sagechain_db"
let db = db_mod.LedgerDB(db_path)

proc serve_file(path, content_type):
    if io.exists(path):
        let content = io.readfile(path)
        return server.response_ok(content, content_type)
    return server.response_not_found("File not found")

proc handle_index(req):
    return serve_file("SageChain/public/index.html", "text/html")

proc handle_app_js(req):
    return serve_file("SageChain/public/app.js", "application/javascript")

proc handle_style_css(req):
    return serve_file("SageChain/public/style.css", "text/css")

proc json_stringify(value):
    let cjson_obj = json.cJSON_FromSage(value)
    let json_str = json.cJSON_PrintUnformatted(cjson_obj)
    json.cJSON_Delete(cjson_obj)
    return json_str

proc api_get_blocks(req):
    # Return last 10 blocks
    let height = 0
    let blocks = []
    
    while io.exists(db.height_dir + "/" + str(height) + ".json"):
        height = height + 1
        
    let start = 0
    if height > 10:
        start = height - 10
        
    let i = height - 1
    while i >= start:
        let b = db.get_block_by_height(i)
        if b != nil:
            push(blocks, b)
        i = i - 1
        
    return server.response_json(json_stringify(blocks))

proc api_get_block(req):
    let h_str = ""
    if dict_has(req, "query"):
        let q = req["query"]
        let parts = split(q, "=")
        if len(parts) == 2 and parts[0] == "h":
            h_str = parts[1]
    
    if len(h_str) > 0:
        let h = int(tonumber(h_str))
        let b = db.get_block_by_height(h)
        if b != nil:
            return server.response_json(json_stringify(b))
    return server.response_not_found("Block not found")

proc api_get_tx(req):
    let tx_hash = ""
    if dict_has(req, "query"):
        let q = req["query"]
        let parts = split(q, "=")
        if len(parts) == 2 and parts[0] == "hash":
            tx_hash = parts[1]
            
    if len(tx_hash) > 0:
        let tx = db.get_transaction(tx_hash)
        if tx != nil:
            return server.response_json(json_stringify(tx))
    return server.response_not_found("Transaction not found")

let srv = server.create_server("0.0.0.0", 8080)
server.get_route(srv["router"], "/", handle_index)
server.get_route(srv["router"], "/app.js", handle_app_js)
server.get_route(srv["router"], "/style.css", handle_style_css)
server.get_route(srv["router"], "/api/blocks", api_get_blocks)
server.get_route(srv["router"], "/api/block", api_get_block)
server.get_route(srv["router"], "/api/tx", api_get_tx)

print "================================================="
print "  SageChain Explorer"
print "  Running on http://localhost:8080"
print "================================================="

server.listen_and_serve(srv)
