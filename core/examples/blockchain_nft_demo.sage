# examples/blockchain_nft_demo.sage
import blockchain.blockchain as bc
import blockchain.wallet as wallet_mod
import io

let db_path = "./sagechain_nft_db"
if io.exists(db_path):
    println "Cleaning old database..."

# 1. Create a wallet for the artist
let artist = wallet_mod.Wallet(nil)
let alice = wallet_mod.Wallet("alice mnemonic word list sage chain green leaf growth")

println "Artist Address: " + artist.get_address()
println "Alice Address: " + alice.get_address()

# 2. Initialize Blockchain with PoW (Difficulty 1 for demo)
let my_coin = bc.Blockchain(1, db_path)

# 3. Load NFT Contract Source
let nft_source = io.readfile("lib/blockchain/std/nft.sage")
if nft_source == nil:
    println "Error: Could not read nft.sage"
    nft_source = "let action = state['action']; if action == 'mint': println 'MINTING...'"

proc demo():
    println "\n--- Deploying NFT Contract ---"
    let nft_addr = my_coin.deploy_contract(artist.get_address(), nft_source)
    println "NFT Contract Deployed at: " + nft_addr

    # 4. Mint an NFT
    println "\n--- Minting NFT #1 ---"
    let mint_args = {
        "action": "mint",
        "tokenId": 1,
        "to": alice.get_address(),
        "uri": "https://sagechain.io/nft/1"
    }
    my_coin.call_contract(artist.get_address(), nft_addr, mint_args, 0)
    
    println "Mining block to process mint..."
    my_coin.mine_pending_transactions(artist.get_address())

    # 5. Check Ownership
    println "\n--- Verifying Ownership ---"
    let nft_state = my_coin.db.get_contract_state(nft_addr)
    let tokens = nft_state["state"]["tokens"]
    if dict_has(tokens, "1"):
        println "Token #1 Owner: " + tokens["1"]
    else:
        println "Token #1 not found!"

    # 6. Alice transfers NFT to Bob
    println "\n--- Alice transferring NFT to Bob ---"
    let bob_addr = "0xBob1234567890abcdef"
    let transfer_args = {
        "action": "transfer",
        "tokenId": 1,
        "to": bob_addr
    }
    my_coin.call_contract(alice.get_address(), nft_addr, transfer_args, 0)
    
    println "Mining block to process transfer..."
    my_coin.mine_pending_transactions(artist.get_address())

    # 7. Final Check
    nft_state = my_coin.db.get_contract_state(nft_addr)
    tokens = nft_state["state"]["tokens"]
    println "Final Token #1 Owner: " + tokens["1"]
    
    if tokens["1"] == bob_addr:
        println "✅ NFT Demo Successful!"

demo()
