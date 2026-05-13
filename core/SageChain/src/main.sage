import blockchain.blockchain as bc
import blockchain.wallet as wallet_mod
import blockchain.transaction as tx_mod
import blockchain.net as p2p_mod
import blockchain.rpc as rpc_mod
import blockchain.consensus.pow as pow_mod
import net.server as server
import blockchain.db as db_mod
import io
import json
import thread
import crypto.hash as hash

let DB_PATH = "./sagechain_db"
let EXPLORER_PORT = 8080
let RPC_PORT = 8545
let P2P_PORT = 8333
let PUBLIC_DIR = "SageChain/public"
let WALLET_PATH = "data/main_wallet.json"
let MINING_INTERVAL = 8.0
let GENESIS_FUND = 1000.0

class WalletService:
    proc init(chain, wallet_path):
        self.chain = chain
        self.wallet_path = wallet_path
        self.wallet = self.load_wallet()
        if self.wallet == nil:
            self.wallet = wallet_mod.Wallet(nil)
            self.save_wallet()

    proc load_wallet():
        if not io.exists(self.wallet_path):
            return nil

        let data = io.readfile(self.wallet_path)
        let cjson = json.cJSON_Parse(data)
        let w_dict = json.cJSON_ToSage(cjson)
        json.cJSON_Delete(cjson)

        let w = wallet_mod.Wallet(nil)
        let addr = w_dict["address"]
        let priv = w_dict["private_key"]
        let pub = w_dict["public_key"]
        let mnemonic = ""
        if dict_has(w_dict, "mnemonic"):
            mnemonic = w_dict["mnemonic"]

        w.mnemonic = mnemonic
        w.private_key = priv
        w.addresses = [{"address": addr, "private_key": priv, "public_key": pub, "index": 0}]
        w.address = addr
        return w

    proc save_wallet():
        let w_dict = {
            "address": self.wallet.address,
            "private_key": self.wallet.addresses[0]["private_key"],
            "public_key": self.wallet.addresses[0]["public_key"],
            "mnemonic": self.wallet.mnemonic
        }
        let cjson = json.cJSON_FromSage(w_dict)
        let data = json.cJSON_Print(cjson)
        json.cJSON_Delete(cjson)

        if not io.exists("data"):
            io.mkdir("data")
        io.writefile(self.wallet_path, data)

    proc get_address():
        return self.wallet.address

    proc get_balance(address):
        return self.chain.get_balance(address)

    proc faucet(address, amount):
        let current = self.chain.get_balance(address)
        self.chain.db.save_account_balance(address, current + amount)

        let tx = {
            "sender": "System",
            "receiver": address,
            "amount": amount,
            "timestamp": clock(),
            "hash": hash.sha256_hex(address + str(clock()))
        }
        self.chain.db.save_transaction(tx)
        self.chain.db.append_tx_to_history(address, tx["hash"])
        return tx

    proc send(to, amount):
        if self.get_balance(self.wallet.address) < amount:
            return nil
        let tx = tx_mod.Transaction(self.wallet.address, to, amount, 0, 1)
        self.wallet.sign_transaction(tx)
        let tx_dict = tx.to_dict()
        let ok = self.chain.add_signed_transaction(tx_dict)
        if ok:
            return tx_dict
        return nil

class ExchangeEngine:
    proc init(chain):
        self.chain = chain
        self.orders = []
        self.trades = []
        self.next_order_id = 1
        self.next_trade_id = 1

    proc place_order(owner, side, amount, price):
        if side != "buy" and side != "sell":
            return nil
        let order = {
            "id": self.next_order_id,
            "owner": owner,
            "side": side,
            "price": price,
            "amount": amount,
            "remaining": amount,
            "status": "open",
            "created": clock()
        }
        self.next_order_id = self.next_order_id + 1
        push(self.orders, order)
        self.match_orders()
        return order

    proc match_orders():
        let bids = []
        let asks = []
        for o in self.orders:
            if o["status"] == "open":
                if o["side"] == "buy":
                    push(bids, o)
                else:
                    push(asks, o)

        if len(bids) == 0 or len(asks) == 0:
            return []

        let trades = []
        while len(bids) > 0 and len(asks) > 0:
            let best_buy_index = 0
            for i in range(1, len(bids)):
                if bids[i]["price"] > bids[best_buy_index]["price"]:
                    best_buy_index = i

            let best_sell_index = 0
            for i in range(1, len(asks)):
                if asks[i]["price"] < asks[best_sell_index]["price"]:
                    best_sell_index = i

            let buy = bids[best_buy_index]
            let sell = asks[best_sell_index]
            if buy["price"] < sell["price"]:
                break

            let size = buy["remaining"]
            if sell["remaining"] < size:
                size = sell["remaining"]

            let price = (buy["price"] + sell["price"]) / 2.0
            let trade = {
                "id": self.next_trade_id,
                "buy_order": buy["id"],
                "sell_order": sell["id"],
                "price": price,
                "amount": size,
                "timestamp": clock()
            }
            self.next_trade_id = self.next_trade_id + 1
            push(self.trades, trade)
            push(trades, trade)

            buy["remaining"] = buy["remaining"] - size
            sell["remaining"] = sell["remaining"] - size
            if buy["remaining"] <= 0:
                buy["status"] = "filled"
            if sell["remaining"] <= 0:
                sell["status"] = "filled"

            let new_bids = []
            for o in bids:
                if o["status"] == "open":
                    push(new_bids, o)
            bids = new_bids

            let new_asks = []
            for o in asks:
                if o["status"] == "open":
                    push(new_asks, o)
            asks = new_asks
        return trades

    proc get_orderbook():
        let result = {"bids": [], "asks": []}
        for o in self.orders:
            if o["status"] == "open":
                if o["side"] == "buy":
                    push(result["bids"], o)
                else:
                    push(result["asks"], o)
        return result

    proc get_trade_history():
        return self.trades

proc serve_file(path, content_type):
    if io.exists(path):
        let content = io.readfile(path)
        return server.response_ok(content, content_type)
    return server.response_not_found("File not found")

proc parse_query(req, key):
    if dict_has(req, "query") and len(req["query"]) > 0:
        let parts = split(req["query"], "&")
        for p in parts:
            let kv = split(p, "=")
            if len(kv) == 2 and kv[0] == key:
                return kv[1]
    return ""

proc handle_index(req):
    return serve_file(PUBLIC_DIR + "/index.html", "text/html")

proc handle_app_js(req):
    return serve_file(PUBLIC_DIR + "/app.js", "application/javascript")

proc handle_style_css(req):
    return serve_file(PUBLIC_DIR + "/style.css", "text/css")

proc json_stringify(value):
    let cjson = json.cJSON_FromSage(value)
    let str = json.cJSON_PrintUnformatted(cjson)
    json.cJSON_Delete(cjson)
    return str

proc api_get_blocks(req):
    let height = 0
    let blocks = []
    while io.exists(chain.db.height_dir + "/" + str(height) + ".json"):
        let b = chain.db.get_block_by_height(height)
        if b != nil:
            push(blocks, b)
        height = height + 1

    let start = 0
    if len(blocks) > 10:
        start = len(blocks) - 10
    let recent = []
    for i in range(start, len(blocks)):
        push(recent, blocks[i])
    return server.response_json(json_stringify(recent))

proc api_get_block(req):
    let h_str = parse_query(req, "h")
    if len(h_str) > 0:
        let h = int(tonumber(h_str))
        let b = chain.get_block_by_height(h)
        if b != nil:
            return server.response_json(json_stringify(b))
    return server.response_not_found("Block not found")

proc api_get_tx(req):
    let tx_hash = parse_query(req, "hash")
    if len(tx_hash) > 0:
        let tx = chain.get_transaction_by_hash(tx_hash)
        if tx != nil:
            return server.response_json(json_stringify(tx))
    return server.response_not_found("Transaction not found")

proc api_wallet_info(req):
    let info = {"address": wallet_service.get_address(), "balance": wallet_service.get_balance(wallet_service.get_address())}
    return server.response_json(json_stringify(info))

proc api_wallet_balance(req):
    let address = parse_query(req, "address")
    if len(address) == 0:
        address = wallet_service.get_address()
    let balance = wallet_service.get_balance(address)
    return server.response_json(json_stringify({"address": address, "balance": balance}))

proc api_wallet_send(req):
    if req["method"] != "POST":
        return server.response_error(405, "Method Not Allowed")
    let payload = json.parse(req["body"])
    if payload == nil or not dict_has(payload, "to") or not dict_has(payload, "amount"):
        return server.response_error(400, "Invalid payload")

    let signed = wallet_service.send(payload["to"], payload["amount"])
    if signed == nil:
        return server.response_error(400, "Unable to send transaction")
    return server.response_json(json_stringify(signed))

proc api_faucet(req):
    let address = parse_query(req, "address")
    let amount = 100.0
    if len(address) == 0:
        return server.response_error(400, "Address required")
    let tx = wallet_service.faucet(address, amount)
    return server.response_json(json_stringify(tx))

proc api_orderbook(req):
    return server.response_json(json_stringify(exchange.get_orderbook()))

proc api_trade_history(req):
    return server.response_json(json_stringify(exchange.get_trade_history()))

proc api_place_order(req):
    if req["method"] != "POST":
        return server.response_error(405, "Method Not Allowed")
    let payload = json.parse(req["body"])
    if payload == nil or not dict_has(payload, "owner") or not dict_has(payload, "side") or not dict_has(payload, "amount") or not dict_has(payload, "price"):
        return server.response_error(400, "Invalid payload")
    let order = exchange.place_order(payload["owner"], payload["side"], payload["amount"], payload["price"])
    if order == nil:
        return server.response_error(400, "Order could not be placed")
    return server.response_json(json_stringify(order))

proc rpc_runner(dummy):
    rpc_srv.start()

proc p2p_runner(dummy):
    p2p_node.start()

let consensus = pow_mod.PowConsensus(nil, 3)
let chain = bc.Blockchain(consensus, DB_PATH)
consensus.blockchain = chain
let wallet_service = WalletService(chain, WALLET_PATH)
let exchange = ExchangeEngine(chain)

# Ensure wallet has a faucet balance for demo use
if wallet_service.get_balance(wallet_service.get_address()) < GENESIS_FUND:
    wallet_service.faucet(wallet_service.get_address(), GENESIS_FUND)

# Deploy staking contract if necessary
if len(chain.contracts) == 0:
    let staking_source = io.readfile("lib/blockchain/staking.sage")
    let staking_addr = chain.deploy_contract(wallet_service.get_address(), staking_source)
    print "Staking contract queued for deployment at " + staking_addr

let rpc_srv = rpc_mod.RPCServer(chain, RPC_PORT)
let p2p_node = p2p_mod.P2PNode(chain, P2P_PORT)
let explorer_srv = server.create_server("0.0.0.0", EXPLORER_PORT)
server.get_route(explorer_srv["router"], "/", handle_index)
server.get_route(explorer_srv["router"], "/app.js", handle_app_js)
server.get_route(explorer_srv["router"], "/style.css", handle_style_css)
server.get_route(explorer_srv["router"], "/api/blocks", api_get_blocks)
server.get_route(explorer_srv["router"], "/api/block", api_get_block)
server.get_route(explorer_srv["router"], "/api/tx", api_get_tx)
server.get_route(explorer_srv["router"], "/api/wallet", api_wallet_info)
server.get_route(explorer_srv["router"], "/api/wallet/balance", api_wallet_balance)
server.post_route(explorer_srv["router"], "/api/wallet/send", api_wallet_send)
server.get_route(explorer_srv["router"], "/api/faucet", api_faucet)
server.get_route(explorer_srv["router"], "/api/orderbook", api_orderbook)
server.post_route(explorer_srv["router"], "/api/order", api_place_order)
server.get_route(explorer_srv["router"], "/api/trades", api_trade_history)

print "================================================="
print "  SageChain Main Node"
print "  Explorer: http://localhost:" + str(EXPLORER_PORT)
print "  RPC:      http://localhost:" + str(RPC_PORT) + "/rpc"
print "  P2P Port: " + str(P2P_PORT)
print "  Wallet:   " + wallet_service.get_address()
print "================================================="

proc mining_worker(miner_address):
    while true:
        if len(chain.mempool) > 0:
            let blk = chain.mine_pending_transactions(miner_address)
            if blk != nil:
                p2p_node.broadcast("new_block", blk.to_dict())
        else:
            chain.mine_pending_transactions(miner_address)
        thread.sleep(1)

proc run_services():
    thread.spawn(rpc_runner, 0)
    thread.spawn(p2p_runner, 0)
    thread.spawn(mining_worker, wallet_service.get_address())
    server.listen_and_serve(explorer_srv)

run_services()
