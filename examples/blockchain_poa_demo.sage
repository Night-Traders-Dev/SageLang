# examples/blockchain_poa_demo.sage
import blockchain.blockchain as bc
import blockchain.consensus.poa as poa_mod
import blockchain.wallet as wallet_mod
import io

let db_path = "./sagechain_poa_db"
if io.exists(db_path):
    # Clean up for demo
    print "Cleaning old database..."

# 1. Create authorities
let auth_wallet = wallet_mod.Wallet(nil)
let authorities = ["System", auth_wallet.get_address()]

print "Authorities: " + str(authorities)

# 2. Initialize with PoA consensus
let consensus = poa_mod.PoAConsensus(nil, authorities)
let my_coin = bc.Blockchain(consensus, db_path)
consensus.blockchain = my_coin

print "================================================="
print "  SageChain PoA Demo"
print "  Authorized Miner: " + auth_wallet.get_address()
print "================================================="

# 3. Try to seal a block as an authority
print "Adding transaction..."
my_coin.add_transaction(auth_wallet.get_address(), "0xAlice", 100)

proc demo():
    print "Sealing block as authority..."
    let blk = my_coin.mine_pending_transactions(auth_wallet.get_address())
    
    if blk != nil:
        print "✅ Block Sealed successfully!"
        print "Block Hash: " + blk.hash
        print "State Root: " + blk.state_root
    else:
        print "❌ Failed to seal block"

    # 4. Try to seal as non-authority
    print ""
    print "Trying to seal as unauthorized user..."
    let fake_blk = my_coin.mine_pending_transactions("0xEvilMiner")
    if fake_blk == nil:
        print "✅ Correctly rejected unauthorized miner"
    else:
        print "❌ SECURITY ERROR: Unauthorized miner was allowed to seal block!"

demo()
