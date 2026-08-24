# examples/blockchain_demo.sage

import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod
import sys

let db_path = "data/basic_test"
sys.exec("rm -rf " + db_path)

print "Creating Sage Blockchain..."
let my_coin = bc_mod.Blockchain(2, db_path) # Difficulty 2

print "Creating wallets..."
let alice = wallet_mod.Wallet()
let bob = wallet_mod.Wallet()
let charlie = wallet_mod.Wallet()

# Fund Alice from the System mint
let funding = {"sender": "System", "receiver": alice.address, "amount": 200, "nonce": 0, "chain_id": 1, "timestamp": clock()}
funding["hash"] = "funding-1"
push(my_coin.mempool, funding)

print "Mining block 1..."
my_coin.mine_pending_transactions("Miner-1")

print "Transferring with signed transactions..."
let t1 = {"sender": alice.address, "receiver": bob.address, "amount": 100, "nonce": 0, "chain_id": 1, "timestamp": clock()}
alice.sign_transaction(t1)
if not my_coin.add_signed_transaction(t1):
    print "tx rejected!"

let t2 = {"sender": bob.address, "receiver": charlie.address, "amount": 50, "nonce": 0, "chain_id": 1, "timestamp": clock()}
bob.sign_transaction(t2)
if not my_coin.add_signed_transaction(t2):
    print "tx rejected!"

print "Mining block 2..."
my_coin.mine_pending_transactions("Miner-1")

print "Blockchain valid? " + str(my_coin.is_chain_valid())

# Display the chain
for block in my_coin.chain:
    print "Block " + str(block.index)
    print "  Hash: " + block.hash
    print "  Prev: " + block.previous_hash
    print "  Txs Count: " + str(len(block.transactions))

print "\nBalances:"
print "  Alice: " + str(my_coin.get_balance(alice.address))
print "  Bob: " + str(my_coin.get_balance(bob.address))
print "  Charlie: " + str(my_coin.get_balance(charlie.address))
print "  Miner-1: " + str(my_coin.get_balance("Miner-1"))

# Try to tamper with the chain
print "\nTampering with block 2 (rewriting a transaction amount)..."
let victim = my_coin.chain[2].transactions[0]
victim["amount"] = victim["amount"] + 10000
print "Blockchain valid? " + str(my_coin.is_chain_valid())
