import blockchain.blockchain as bc
import blockchain.wallet as wallet_mod
import io

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
