# examples/blockchain_db_demo.sage

import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod

let db_path = "data/blockchain"
print "Initializing Database-backed Blockchain at " + db_path
let my_coin = bc_mod.Blockchain(1, db_path)

let alice = wallet_mod.Wallet()
let miner = wallet_mod.Wallet()

if len(my_coin.chain) <= 1:
    print "\nFirst Run: Mining some blocks..."
    my_coin.add_transaction("System", alice.address, 1000)
    my_coin.mine_pending_transactions(miner.address)
    
    my_coin.add_transaction(alice.address, "Bob", 100)
    my_coin.mine_pending_transactions(miner.address)
    
    print "Current Height: " + str(len(my_coin.chain))
    print "Alice Balance: " + str(my_coin.get_balance(alice.address))
    print "Miner Balance: " + str(my_coin.get_balance(miner.address))
    print "\nRestart the script to see persistence!"
else:
    print "\nSubsequent Run: Data recovered from DB!"
    print "Current Height: " + str(len(my_coin.chain))
    # Note: we'd need to save/load wallet info too for a real app, 
    # but here we'll just check if there's data in the chain.
    let last_block = my_coin.get_latest_block()
    print "Latest Block Hash: " + last_block.hash
    print "Total Mined: " + str(my_coin.total_mined) + " ORBIT"
