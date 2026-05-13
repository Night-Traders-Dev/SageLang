# examples/blockchain_orbit_demo.sage

import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod
import sys

let db_path = "data/orbit_test"
sys.exec("rm -rf " + db_path)

print "Initializing Orbit Blockchain..."
let my_coin = bc_mod.Blockchain(1, db_path) # Low difficulty for faster simulation

# Create wallets for users
let alice = wallet_mod.Wallet()
let bob = wallet_mod.Wallet()
let charlie = wallet_mod.Wallet()
let miner = wallet_mod.Wallet()

# Register the miner node
my_coin.register_node(miner.address)

print "\nStep 1: Mining with low user count (1 registered node)"
print "Active Users: " + str(my_coin.get_active_user_count())
my_coin.add_transaction(alice.address, bob.address, 10)
my_coin.mine_pending_transactions(miner.address)

print "\nStep 2: Simulating more transactions to increase user count"
my_coin.add_transaction(bob.address, charlie.address, 5)
my_coin.add_transaction(charlie.address, alice.address, 2)
my_coin.mine_pending_transactions(miner.address)

print "\nStep 3: Checking Miner Stats"
let node = my_coin.nodes[miner.address]
print "Miner Score: " + str(node.score)
print "Blocks Mined: " + str(node.total_blocks_mined)

print "\nStep 4: Simulating block height increase (reward halving effect)"
# We can't easily jump block height without mining, but we can see the rate formula
import blockchain.orbit as orbit
let current_mined = my_coin.total_mined
let user_count = my_coin.get_active_user_count()

print "Current Stats: Mined=" + str(current_mined) + ", Users=" + str(user_count)
print "Mining rate at block 0:     " + str(orbit.calculate_mining_rate(user_count, current_mined, 0, 1.0))
print "Mining rate at block 100k:  " + str(orbit.calculate_mining_rate(user_count, current_mined, 100000, 1.0))
print "Mining rate at block 200k:  " + str(orbit.calculate_mining_rate(user_count, current_mined, 200000, 1.0))

print "\nStep 5: Simulating node boost effect"
print "Mining rate (Score 0.0):    " + str(orbit.calculate_mining_rate(user_count, current_mined, 0, 0.0))
print "Mining rate (Score 1.0):    " + str(orbit.calculate_mining_rate(user_count, current_mined, 0, 1.0))

print "\nFinal Blockchain State:"
print "Total Mined: " + str(my_coin.total_mined) + " ORBIT"
print "Miner Balance: " + str(my_coin.get_balance(miner.address))
