# lib/blockchain/std/nft.sage
# SNFT-721 Standard: Non-Fungible Token Standard for SageChain

# Input Context (from state):
#   state["sender"]: caller address
#   state["action"]: "mint", "transfer", "ownerOf", "metadata"
#   state["to"]: recipient (for mint/transfer)
#   state["tokenId"]: ID of the token
#   state["uri"]: Metadata URI (for mint)

let sender = state["sender"]
let action = state["action"]

if not dict_has(state, "tokens"):
    state["tokens"] = {} # tokenId -> owner
if not dict_has(state, "metadata"):
    state["metadata"] = {} # tokenId -> uri
if not dict_has(state, "balances"):
    state["balances"] = {} # owner -> count
if not dict_has(state, "name"):
    state["name"] = "SageNFT"
if not dict_has(state, "symbol"):
    state["symbol"] = "SNFT"

let results = []

if action == "mint":
    let tokenId = str(state["tokenId"])
    let to = state["to"]
    let uri = state["uri"]
    
    if dict_has(state["tokens"], tokenId):
        print "Mint Error: Token " + str(tokenId) + " already exists"
    else:
        state["tokens"][tokenId] = to
        state["metadata"][tokenId] = uri
        
        # Update balance
        let b = 0
        if dict_has(state["balances"], to):
            b = state["balances"][to]
        state["balances"][to] = b + 1
        
        print "SUCCESS: Minted token " + str(tokenId) + " to " + to
        results = [{"event": "Mint", "to": to, "tokenId": tokenId}]

if action == "transfer":
    let tokenId = str(state["tokenId"])
    let to = state["to"]
    
    if not dict_has(state["tokens"], tokenId):
        print "Transfer Error: Token " + str(tokenId) + " does not exist"
    else:
        let owner = state["tokens"][tokenId]
        if owner != sender:
            print "Transfer Error: Sender " + sender + " does not own token " + str(tokenId)
        else:
            state["tokens"][tokenId] = to
            
            # Update balances
            state["balances"][owner] = state["balances"][owner] - 1
            let b_to = 0
            if dict_has(state["balances"], to):
                b_to = state["balances"][to]
            state["balances"][to] = b_to + 1
            
            print "SUCCESS: Transferred token " + str(tokenId) + " from " + owner + " to " + to
            results = [{"event": "Transfer", "from": owner, "to": to, "tokenId": tokenId}]

if action == "ownerOf":
    let tokenId = str(state["tokenId"])
    if dict_has(state["tokens"], tokenId):
        results = state["tokens"][tokenId]
    else:
        results = nil

if action == "metadata":
    let tokenId = str(state["tokenId"])
    if dict_has(state["metadata"], tokenId):
        results = state["metadata"][tokenId]
    else:
        results = nil

# Return results
results
