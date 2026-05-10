# lib/blockchain/wallet.sage
# Hierarchical Deterministic (HD) Wallet Simulation for SageChain

import crypto.hash as hash
import crypto

class Wallet:
    proc init(mnemonic):
        if mnemonic == nil:
            self.mnemonic = self.generate_mnemonic()
        else:
            self.mnemonic = mnemonic
        
        # Derive master seed from mnemonic
        self.seed = hash.sha256_hex(self.mnemonic)
        self.addresses = []
        # Generate first address by default
        self.derive_address(0)

    proc generate_mnemonic():
        # Simulation: pick 12 random words from a small list
        let words = ["sage", "chain", "green", "leaf", "growth", "smart", "contract", "node", "decent", "block", "peer", "secure"]
        let result = ""
        for i in range(12):
            # In real Sage, we'd use a better random source
            let idx = tonumber(str(clock() * 1000)) % 12
            result = result + words[idx]
            if i < 11: result = result + " "
        return result

    proc derive_address(index):
        # HD Derivation: Hash(seed + index)
        let priv_key = hash.sha256_hex(self.seed + str(index))
        # Address is first 40 chars of hash of private key
        let addr = "0x" + hash.sha256_hex(priv_key)[:40]
        let w_obj = {"address": addr, "private_key": priv_key, "index": index}
        push(self.addresses, w_obj)
        return addr

    proc get_address():
        return self.addresses[0]["address"]

    proc sign_transaction(tx):
        # Phase 1: Real signature verification
        let msg = str(tx["sender"]) + str(tx["receiver"]) + str(tx["amount"])
        # Find which of our derived addresses is the sender
        let priv = nil
        for w in self.addresses:
            if w["address"] == tx["sender"]:
                priv = w["private_key"]
                break
        
        if priv == nil:
            print "Error: Wallet does not own sender address " + tx["sender"]
            return
            
        tx["signature"] = hash.sha256_hex(msg + priv)
        tx["public_key"] = tx["sender"] # Simplified: Address acts as public key
