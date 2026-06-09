# lib/blockchain/block.sage

import crypto.hash as hash

class Block:
    proc init(index, transactions, previous_hash, difficulty):
        self.index = index
        self.timestamp = clock()
        self.transactions = transactions
        self.previous_hash = previous_hash
        self.difficulty = difficulty
        self.nonce = 0
        self.state_root = "0"
        self.hash = self.calculate_hash()

    proc calculate_hash():
        # Fast path hashing: combine key fields
        let data = str(self.index) + str(self.timestamp) + str(self.previous_hash) + str(self.nonce) + str(self.state_root)
        # Avoid stringifying large transaction lists; use count as proxy for speed
        if len(self.transactions) > 0:
            data = data + ":" + str(len(self.transactions))
            
        return hash.sha256_hex(data)

    proc mine():
        let target = ""
        let i = 0
        while i < self.difficulty:
            target = target + "0"
            i = i + 1
        
        while self.hash[:self.difficulty] != target:
            self.nonce = self.nonce + 1
            self.hash = self.calculate_hash()
        
        return self.hash

    proc to_dict():
        let d = {}
        d["index"] = self.index
        d["timestamp"] = self.timestamp
        d["transactions"] = self.transactions
        d["previous_hash"] = self.previous_hash
        d["difficulty"] = self.difficulty
        d["nonce"] = self.nonce
        d["hash"] = self.hash
        d["state_root"] = self.state_root
        return d
