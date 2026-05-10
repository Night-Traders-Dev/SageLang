# examples/blockchain_wallet_demo.sage

import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod
import blockchain.transaction as tx_mod
import sys

let db_path = "data/wallet_test"
sys.exec("rm -rf " + db_path)

print "Initializing Sage Blockchain with Wallet Support..."
let my_coin = bc_mod.Blockchain(2, db_path)

let wallet_a = wallet_mod.Wallet()
let wallet_b = wallet_mod.Wallet()
let miner_wallet = wallet_mod.Wallet()

print "Wallet A Address: " + wallet_a.address
print "Wallet B Address: " + wallet_b.address
print "Miner Wallet Address: " + miner_wallet.address

print "\nCreating a signed transaction from A to B..."
let tx1 = tx_mod.Transaction(wallet_a.address, wallet_b.address, 100)
wallet_a.sign_transaction(tx1)

print "Submitting transaction..."
if my_coin.add_signed_transaction(tx1):
    print "Transaction accepted."
else:
    print "Transaction rejected!"

print "\nMining pending transactions..."
my_coin.mine_pending_transactions(miner_wallet.address)

print "\nCreating an UNSIGNED transaction from B to A..."
let tx2 = tx_mod.Transaction(wallet_b.address, wallet_a.address, 50)
# Skip signing

print "Submitting transaction..."
if my_coin.add_signed_transaction(tx2):
    print "Transaction accepted."
else:
    print "Transaction rejected!"

print "\nMining pending transactions..."
my_coin.mine_pending_transactions(miner_wallet.address)

print "\nBlockchain valid? " + str(my_coin.is_chain_valid())

print "\nFinal Balances:"
print "  Wallet A: " + str(my_coin.get_balance(wallet_a.address))
print "  Wallet B: " + str(my_coin.get_balance(wallet_b.address))
print "  Miner:    " + str(my_coin.get_balance(miner_wallet.address))
