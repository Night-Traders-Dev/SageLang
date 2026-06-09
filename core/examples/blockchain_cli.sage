# examples/blockchain_cli.sage

import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod
import blockchain.transaction as tx_mod
import io
import json
import sys
import thread

let DB_PATH = "data/cli_blockchain"
let WALLET_PATH = "data/cli_wallet.json"

# ============================================================================
# Wallet Persistence
# ============================================================================

proc load_wallet():
    if not io.exists(WALLET_PATH):
        return nil
    let data = io.readfile(WALLET_PATH)
    let cjson = json.cJSON_Parse(data)
    let w_dict = json.cJSON_ToSage(cjson)
    json.cJSON_Delete(cjson)
    
    let w = wallet_mod.Wallet(nil)
    w.private_key = w_dict["private_key"]
    w.address = w_dict["address"]
    return w

proc save_wallet(w):
    let w_dict = {}
    w_dict["private_key"] = w.private_key
    w_dict["address"] = w.address
    let cjson = json.cJSON_FromSage(w_dict)
    let data = json.cJSON_Print(cjson)
    json.cJSON_Delete(cjson)
    
    sys.exec("mkdir -p data")
    io.writefile(WALLET_PATH, data)

let running = true

# ============================================================================
# Background Mining
# ============================================================================

proc mining_worker(bc, miner_address):
    print "\n[Node] Mining worker started for " + miner_address
    while running:
        # Check if there are transactions to mine
        if len(bc.mempool) > 0:
            bc.mine_pending_transactions(miner_address)
        else:
            # Still mine periodically for rewards even if no user tx
            bc.mine_pending_transactions(miner_address)
            thread.sleep(10)
        thread.sleep(1)
    print "[Node] Mining worker stopped."

# ============================================================================
# Main CLI Loop
# ============================================================================

print "=== Sage Blockchain Terminal ==="
print "Loading blockchain..."
let my_coin = bc_mod.Blockchain(2, DB_PATH)

let wallet = load_wallet()
if wallet == nil:
    print "No wallet found. Creating new one..."
    wallet = wallet_mod.Wallet(nil)
    save_wallet(wallet)
    print "New wallet address: " + wallet.address
else:
    print "Wallet loaded: " + wallet.address

# Register node
my_coin.register_node(wallet.address)

# Staking contract deployment
let staking_addr = "0xstaking_contract_v1"
if not dict_has(my_coin.contracts, staking_addr):
    let staking_source = io.readfile("lib/blockchain/staking.sage")
    let addr = my_coin.deploy_contract(wallet.address, staking_source)
    print "Staking contract deployed at: " + addr
    staking_addr = addr

# Start mining in background
thread.spawn(mining_worker, my_coin, wallet.address)

proc print_help():
    print "\nAvailable Commands:"
    print "  balance          - Check your wallet balance"
    print "  history          - View transaction history"
    print "  send <to> <amt>  - Send ORBIT to another address"
    print "  stake <amt>      - Stake ORBIT for 5% APR (7 day lock)"
    print "  claim            - Claim staking rewards"
    print "  unstake          - Unstake ORBIT and rewards"
    print "  stats            - View blockchain and node stats"
    print "  help             - Show this help"
    print "  exit             - Exit terminal"

print_help()

while true:
    let cmd_line = input("> ")
    if cmd_line == nil:
        break
    
    let cmd_line_stripped = strip(cmd_line)
    if cmd_line_stripped == "":
        continue
        
    let parts = split(cmd_line_stripped, " ")
    let cmd = parts[0]
    
    if cmd == "exit":
        print "Goodbye!"
        running = false
        thread.sleep(1)
        break
        
    if cmd == "help":
        print_help()
        continue
        
    if cmd == "balance":
        let bal = my_coin.get_balance(wallet.address)
        print "Your balance: " + str(bal) + " ORBIT"
        continue
        
    if cmd == "history":
        let history = my_coin.get_transaction_history(wallet.address)
        print "\nTransaction History:"
        for tx in history:
            let t_type = "Transfer"
            if dict_has(tx, "type"):
                t_type = tx["type"]
            print "  [" + t_type + "] " + tx["sender"] + " -> " + str(tx["receiver"]) + ": " + str(tx["amount"])
        continue
        
    if cmd == "stats":
        print "\nBlockchain Stats:"
        print "  Height:        " + str(len(my_coin.chain))
        print "  Total Mined:   " + str(my_coin.total_mined) + " ORBIT"
        print "  Active Users:  " + str(my_coin.get_active_user_count())
        print "  Mempool Size:  " + str(len(my_coin.mempool))
        print "Node Stats:"
        let node = my_coin.nodes[wallet.address]
        print "  Address:       " + node.address
        print "  Score:         " + str(node.score)
        print "  Blocks Mined:  " + str(node.total_blocks_mined)
        continue
        
    if cmd == "send":
        if len(parts) < 3:
            print "Usage: send <to_address> <amount>"
            continue
        let to_addr = parts[1]
        let amount = tonumber(parts[2])
        
        if my_coin.get_balance(wallet.address) < amount:
            print "Error: Insufficient balance"
            continue
            
        let tx = tx_mod.Transaction(wallet.address, to_addr, amount)
        wallet.sign_transaction(tx)
        if my_coin.add_signed_transaction(tx):
            print "Transaction submitted to mempool."
        else:
            print "Error submitting transaction."
        continue

    if cmd == "stake":
        if len(parts) < 2:
            print "Usage: stake <amount>"
            continue
        let amount = tonumber(parts[1])
        let args = {"action": "stake", "duration": 86400 * 7}
        if my_coin.call_contract(wallet.address, staking_addr, args, amount):
            print "Stake request submitted."
        continue
        
    if cmd == "claim":
        let args = {"action": "claim"}
        if my_coin.call_contract(wallet.address, staking_addr, args, 0):
            print "Claim request submitted."
        continue
        
    if cmd == "unstake":
        let args = {"action": "unstake"}
        if my_coin.call_contract(wallet.address, staking_addr, args, 0):
            print "Unstake request submitted."
        continue

    print "Unknown command: " + cmd
