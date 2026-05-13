# lib/blockchain/merkle.sage
# Verifiable Ledger (Merkleization) and State Tries for Sage Blockchain

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

# Hex-based Radix Trie for Global World State
class StateTrie:
    proc init():
        self.root = {"type": "branch", "children": {}}

    proc update(address, value):
        let path = address
        if startswith(path, "0x"):
            path = path[2:]
        
        let current = self.root
        let i = 0
        let plen = len(path)
        while i < plen:
            let char = path[i]
            if not dict_has(current["children"], char):
                current["children"][char] = {"type": "branch", "children": {}}
            current = current["children"][char]
            i = i + 1
            
        current["type"] = "leaf"
        current["value"] = value

    proc get(address):
        let path = address
        if startswith(path, "0x"):
            path = path[2:]
            
        let current = self.root
        let i = 0
        let plen = len(path)
        while i < plen:
            let char = path[i]
            if not dict_has(current["children"], char):
                return nil
            current = current["children"][char]
            i = i + 1
            
        if current["type"] == "leaf":
            return current["value"]
        return nil

    proc get_root_hash():
        # Temporary flat hash to avoid recursion depth issues
        return hash.sha256_hex("state_root_proxy")
