# lib/blockchain/merkle.sage
# Verifiable Ledger (Merkleization) for Sage Blockchain (Phase 3)

import crypto.hash as hash

class MerkleTree:
    proc init(data_list):
        self.leaves = []
        for item in data_list:
            push(self.leaves, hash.sha256_hex(str(item)))
        
        if len(self.leaves) == 0:
            push(self.leaves, hash.sha256_hex("empty"))
            
        self.root = self.build_tree(self.leaves)

    proc build_tree(nodes):
        if len(nodes) == 1:
            return nodes[0]
            
        let next_level = []
        let i = 0
        while i < len(nodes):
            let left = nodes[i]
            let right = left
            if i + 1 < len(nodes):
                right = nodes[i+1]
            
            push(next_level, hash.sha256_hex(left + right))
            i = i + 2
            
        return self.build_tree(next_level)

    proc get_root():
        return self.root
