# lib/blockchain/wallet.sage
# Hierarchical Deterministic (HD) Wallet Simulation for SageChain

import crypto.hash as hash
import blockchain.crypto as bc_crypto

class Wallet:
    proc init(mnemonic=nil):
        if mnemonic == nil:
            self.mnemonic = self.generate_mnemonic()
        else:
            self.mnemonic = mnemonic
        
        # Derive master seed from mnemonic
        self.seed = hash.sha256_hex(self.mnemonic)
        self.addresses = []
        # Generate first address by default
        self.derive_address(0)
        self.address = self.addresses[0]["address"]
        self.private_key = self.addresses[0]["private_key"]

    proc generate_mnemonic():
        # Simulation: pick 12 random words from a small list
        let words = ["sage", "chain", "green", "leaf", "growth", "smart", "contract", "node", "decent", "block", "peer", "secure"]
        let result = ""
        for i in range(12):
            # In real Sage, we'd use a better random source
            let idx = tonumber(str(clock() * 1000)) % 12
            result = result + words[idx]
            if i < 11:
                result = result + " "
        return result

    proc derive_address(index):
        # HD Derivation: Hash(seed + index)
        let priv_key = hash.sha256_hex(self.seed + str(index))
        let pub_key = hash.sha256_hex(priv_key)
        # Address is first 40 chars of public key hash
        let addr = "0x" + pub_key[:40]
        let w_obj = {"address": addr, "private_key": priv_key, "public_key": pub_key, "index": index}
        push(self.addresses, w_obj)
        return addr

    proc get_address():
        return self.addresses[0]["address"]

    proc transaction_message(tx):
        let sender = ""
        let receiver = ""
        let amount = 0.0
        let nonce = 0
        let chain_id = 0
        let tx_type = "transfer"
        let timestamp = 0

        if type(tx) == "dict":
            if dict_has(tx, "sender"):
                sender = tx["sender"]
            if dict_has(tx, "receiver"):
                receiver = tx["receiver"]
            if dict_has(tx, "amount"):
                amount = tx["amount"]
            if dict_has(tx, "nonce"):
                nonce = tx["nonce"]
            if dict_has(tx, "chain_id"):
                chain_id = tx["chain_id"]
            if dict_has(tx, "type"):
                tx_type = tx["type"]
            if dict_has(tx, "timestamp"):
                timestamp = tx["timestamp"]
        else:
            sender = tx.sender
            receiver = tx.receiver
            amount = tx.amount
            nonce = tx.nonce
            chain_id = tx.chain_id
            if dict_has(tx, "type"):
                tx_type = tx["type"]
            timestamp = tx.timestamp

        return str(sender) + ":" + str(receiver) + ":" + str(amount) + ":" + str(nonce) + ":" + str(chain_id) + ":" + str(tx_type) + ":" + str(timestamp)

    proc sign_transaction(tx):
        let is_dict = type(tx) == "dict"
        let tx_dict = tx
        if not is_dict and hasattr(tx, "to_dict"):
            tx_dict = tx.to_dict()

        let tx_sender = tx_dict["sender"]
        let priv = nil
        let pub = nil
        for w in self.addresses:
            if w["address"] == tx_sender:
                priv = w["private_key"]
                pub = w["public_key"]
                break

        if priv == nil:
            print "Error: Wallet does not own sender address " + tx_sender
            return

        let msg = self.transaction_message(tx_dict)
        let signature = bc_crypto.sign(msg, priv)
        if is_dict:
            tx_dict["signature"] = signature
            tx_dict["public_key"] = pub
        else:
            tx["signature"] = signature
            tx["public_key"] = pub
