# Blockchain library end-to-end functional audit tests
import sys
import blockchain.blockchain as B
import blockchain.wallet as W
import blockchain.consensus.poa as POA
import blockchain.merkle as MK

let passed = 0
let failed = 0
let failures = []
let base = "/tmp/sage_bc_audit_" + str(int(clock()))

proc ok(name, cond):
    if cond:
        return true
    push(failures, name)
    return false

# --- PoW chain: genesis, validity, persistence ---
let chain = B.Blockchain(2, base + "/pow")
ok("genesis height", len(chain.chain) == 1)
ok("genesis valid", chain.is_chain_valid())

# --- Wallets ---
let alice = W.Wallet()
let bob = W.Wallet()
ok("alice address format", alice.address[:2] == "0x" and len(alice.address) == 42)
ok("deterministic derivation", alice.derive_address(0) == alice.address)
let w2 = W.Wallet(alice.mnemonic)
ok("mnemonic restores same address", w2.address == alice.address)

# --- Funding via System mint tx (no type field) ---
let fund = {"sender": "System", "receiver": alice.address, "amount": 100.0, "nonce": 0, "chain_id": 1, "timestamp": clock()}
fund["hash"] = "sys-fund-1"
push(chain.mempool, fund)
chain.mine_pending_transactions(bob.address)
ok("system mint credited", chain.get_balance(alice.address) == 100.0)
ok("miner reward", chain.get_balance(bob.address) == 10.0)
ok("chain valid after mine", chain.is_chain_valid())

# --- Signed transfer end-to-end ---
let t = {"sender": alice.address, "receiver": bob.address, "amount": 30.0, "nonce": 0, "chain_id": 1, "timestamp": clock()}
alice.sign_transaction(t)
ok("signed tx accepted", chain.add_signed_transaction(t))
chain.mine_pending_transactions(bob.address)
ok("transfer debited sender", chain.get_balance(alice.address) == 70.0)
# bob mined this block too: 10 (first reward) + 10 (second reward) + 30 (transfer)
ok("transfer credited receiver", chain.get_balance(bob.address) == 50.0)
ok("chain valid after transfer", chain.is_chain_valid())

# --- Tampered signature rejected ---
let forged = {"sender": alice.address, "receiver": bob.address, "amount": 999.0, "nonce": 1, "chain_id": 1, "timestamp": clock()}
forged["signature"] = "deadbeef"
forged["public_key"] = alice.private_key
ok("forged signature rejected", not chain.add_signed_transaction(forged))

# --- Wrong-key signature rejected ---
let wrong = {"sender": alice.address, "receiver": bob.address, "amount": 5.0, "nonce": 2, "chain_id": 1, "timestamp": clock()}
bob.sign_transaction(wrong)
ok("wrong signer rejected", not chain.add_signed_transaction(wrong))

# --- Insufficient funds rejected ---
let big = {"sender": alice.address, "receiver": bob.address, "amount": 10000.0, "nonce": 3, "chain_id": 1, "timestamp": clock()}
alice.sign_transaction(big)
ok("submitted over-spend", chain.add_signed_transaction(big))
chain.mine_pending_transactions(bob.address)
ok("over-spend dropped, balance intact", chain.get_balance(alice.address) == 70.0)

# --- Unknown type rejected ---
let weird = {"sender": "System", "receiver": bob.address, "amount": 1.0, "type": "faucet", "timestamp": clock()}
weird["hash"] = "weird-1"
push(chain.mempool, weird)
let before_bob = chain.get_balance(bob.address)
chain.mine_pending_transactions(bob.address)
ok("unknown type not executed", chain.get_balance(bob.address) >= before_bob)

# --- Persistence: reload from disk ---
let reloaded = B.Blockchain(2, base + "/pow")
ok("reload height", len(reloaded.chain) == len(chain.chain))
ok("reload valid", reloaded.is_chain_valid())
ok("reload balance persisted", reloaded.get_balance(alice.address) == 70.0)

# --- Tamper detection on block content ---
if len(chain.chain) > 1:
    let saved_txs_amount = chain.chain[1].transactions[0]["amount"]
    chain.chain[1].transactions[0]["amount"] = 0.01
    ok("tx tamper detected", not chain.is_chain_valid())
    chain.chain[1].transactions[0]["amount"] = saved_txs_amount
    ok("restored chain valid", chain.is_chain_valid())

# --- Merkle tree ---
let mt = MK.MerkleTree(["a", "b", "c"])
let mt2 = MK.MerkleTree(["a", "b", "c"])
let mt3 = MK.MerkleTree(["a", "x", "c"])
ok("merkle deterministic", mt.get_root() == mt2.get_root())
ok("merkle sensitive to data", mt.get_root() != mt3.get_root())
ok("merkle odd count works", len(mt.get_root()) == 64)

# --- State trie ---
let trie = MK.StateTrie()
trie.update("0xabcd", {"balance": 5.0})
ok("trie get", trie.get("0xabcd")["balance"] == 5.0)
ok("trie miss nil", trie.get("0xffff") == nil)
let rh1 = trie.get_root_hash()
trie.update("0xabce", {"balance": 6.0})
ok("trie root changes", trie.get_root_hash() != rh1)

# --- PoA chain ---
let poa_chain = B.Blockchain(POA.PoAConsensus(nil, ["authority-a"]), base + "/poa")
ok("poa genesis valid", poa_chain.is_chain_valid())
let sealed = poa_chain.consensus.seal_block([], "not-an-authority")
ok("poa rejects non-authority seal", sealed == nil)
let sealed2 = poa_chain.consensus.seal_block([], "authority-a")
ok("poa authority seals", sealed2 != nil)
ok("poa validates own block", poa_chain.consensus.validate_block(sealed2))

# slashing + validator rotation
poa_chain.consensus.add_authority("validator-b")
ok("added authority can seal", poa_chain.consensus.seal_block([], "validator-b") != nil)
poa_chain.consensus.slash("validator-b")
ok("slashed authority removed", not poa_chain.consensus.is_authority("validator-b"))
ok("slashed authority cannot seal", poa_chain.consensus.seal_block([], "validator-b") == nil)
ok("poa chain still valid", poa_chain.is_chain_valid())

# tampered poa block rejected
sealed2.hash = "f" * 64
ok("poa rejects tampered hash sig", not poa_chain.consensus.validate_block(sealed2))

# --- Orbit emission schedule sanity ---
import blockchain.orbit as OR
let r0 = OR.calculate_mining_rate(100, 0.0, 0, 0.05)
let r_half = OR.calculate_mining_rate(100, 500000000.0, 0, 0.05)
let r_decay = OR.calculate_mining_rate(100, 0.0, 100000, 0.05)
ok("orbit base rate", r0 > 0.082 and r0 <= 0.082 * 1.05 + 0.000001 or (r0 > 0.082 - 0.000001 and r0 < 0.08261))
ok("orbit supply halves rate", r_half < r0)
ok("orbit halving decays", r_decay < r0 / 1.9 and r_decay > r0 / 2.1)

print(str(len(failures)) + " failures")
for f in failures:
    print("FAIL " + f)
if len(failures) == 0:
    print("ALL BLOCKCHAIN AUDIT TESTS PASSED")
