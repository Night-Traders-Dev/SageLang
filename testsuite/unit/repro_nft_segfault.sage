# EXPECT: error: Unexpected character.
# EXPECT:   --> <vm-compile>:2:20
# EXPECT:   |
# EXPECT: 2 | let sender = state['sender']
# EXPECT:   |                    ^
# EXPECT: Init wallet...
# EXPECT: Artist: initialized
# EXPECT: Init blockchain...
# EXPECT: Blockchain init ok
# EXPECT: Deploying...
import blockchain.blockchain as bc
import blockchain.wallet as wallet_mod
import sys

let db_path = "/tmp/sage_nft_repro_" + str(int(sys.clock() * 1000000))
sys.shell_exec("rm -rf " + db_path)

print "Init wallet..."
let artist = wallet_mod.Wallet(nil)
print "Artist: initialized"

print "Init blockchain..."
let my_coin = bc.Blockchain(1, db_path)
print "Blockchain init ok"

let nft_source = "# NFT Contract\nlet sender = state['sender']\nlet results = []\nresults"
print "Deploying..."
let nft_addr = my_coin.deploy_contract(artist.get_address(), nft_source)
print "Deployed: " + nft_addr

print "Mining..."
my_coin.mine_pending_transactions(artist.get_address())
print "Mined"
