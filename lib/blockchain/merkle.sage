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
# Maps Address (hex) -> State Object (JSON-serialized)
class StateTrie:
    proc init():
        self.root = {"type": "branch", "children": {}}
        self.hash_cache = {}

    proc update(address, value):
        # address is hex string, value is dict
        let path = address
        if startswith(path, "0x"):
            path = path[2:]
        
        self._update_recursive(self.root, path, value)
        # Clear cache since tree changed
        self.hash_cache = {}

    proc _update_recursive(node, path, value):
        if len(path) == 0:
            node["type"] = "leaf"
            node["value"] = value
            return

        let char = path[0]
        let rest = path[1:]
        
        if not dict_has(node["children"], char):
            node["children"][char] = {"type": "branch", "children": {}}
        
        self._update_recursive(node["children"][char], rest, value)

    proc get(address):
        let path = address
        if startswith(path, "0x"):
            path = path[2:]
            
        let current = self.root
        for i in range(len(path)):
            let char = path[i]
            if not dict_has(current["children"], char):
                return nil
            current = current["children"][char]
            
        if current["type"] == "leaf":
            return current["value"]
        return nil

    proc get_root_hash():
        return self._hash_node(self.root)

    proc _hash_node(node):
        # Deterministic hashing of a trie node
        if node["type"] == "leaf":
            return hash.sha256_hex("leaf:" + str(node["value"]))
            
        # Branch node: hash of concatenated child hashes
        let child_data = ""
        # Sorted keys for determinism
        let keys = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"]
        for k in keys:
            if dict_has(node["children"], k):
                child_data = child_data + k + ":" + self._hash_node(node["children"][k])
            else:
                child_data = child_data + k + ":null"
                
        return hash.sha256_hex("branch:" + child_data)
