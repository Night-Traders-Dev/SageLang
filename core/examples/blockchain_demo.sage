# examples/blockchain_demo.sage

import blockchain.blockchain as bc_mod
import sys

let db_path = "data/basic_test"
sys.exec("rm -rf " + db_path)

print "Creating Sage Blockchain..."
let my_coin = bc_mod.Blockchain(2, db_path) # Difficulty 2

print "Mining block 1..."
my_coin.add_transaction("Alice", "Bob", 100)
my_coin.add_transaction("Bob", "Charlie", 50)
my_coin.mine_pending_transactions("Miner-1")

print "Mining block 2..."
my_coin.add_transaction("Charlie", "Alice", 25)
my_coin.mine_pending_transactions("Miner-1")

print "Blockchain valid? " + str(my_coin.is_chain_valid())

# Display the chain
for block in my_coin.chain:
    print "Block " + str(block.index)
    print "  Hash: " + block.hash
    print "  Prev: " + block.previous_hash
    print "  Txs Count: " + str(len(block.transactions))

print "\nBalances:"
print "  Alice: " + str(my_coin.get_balance("Alice"))
print "  Bob: " + str(my_coin.get_balance("Bob"))
print "  Charlie: " + str(my_coin.get_balance("Charlie"))
print "  Miner-1: " + str(my_coin.get_balance("Miner-1"))

# Try to tamper with the chain
print "\nTampering with block 1..."
my_coin.chain[1].transactions = ["Malicious Transaction"]
print "Blockchain valid? " + str(my_coin.is_chain_valid())
