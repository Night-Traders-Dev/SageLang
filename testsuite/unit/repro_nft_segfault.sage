# EXPECT: error: Unexpected character.
# EXPECT:   --> <vm-compile>:2:20
# EXPECT:   |
# EXPECT: 2 | let sender = state['sender']
# EXPECT:   |                    ^
# EXPECT: Init wallet...
# EXPECT: Artist: 0x591ae5da36853445afe704598480b5d0efb0a9ba
# EXPECT: Init blockchain...
# EXPECT: Blockchain init ok
# EXPECT: Deploying...
import blockchain.blockchain as bc
import blockchain.wallet as wallet_mod
import io
import sys

sys.shell_exec("rm -rf ./tmp_db")

print "Init wallet..."
let artist = wallet_mod.Wallet(nil)
print "Artist: " + artist.get_address()

print "Init blockchain..."
let my_coin = bc.Blockchain(1, "./tmp_db")
print "Blockchain init ok"

let nft_source = "# NFT Contract\nlet sender = state['sender']\nlet results = []\nresults"
print "Deploying..."
let nft_addr = my_coin.deploy_contract(artist.get_address(), nft_source)
print "Deployed: " + nft_addr

print "Mining..."
my_coin.mine_pending_transactions(artist.get_address())
print "Mined"
