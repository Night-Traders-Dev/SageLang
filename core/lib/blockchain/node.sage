# lib/blockchain/node.sage

class Node:
    proc init(address):
        self.address = address
        self.score = 1.0  # Initial score (max trust)
        self.uptime = 1.0
        self.total_blocks_mined = 0

    proc update_score(is_reliable):
        if is_reliable:
            self.score = self.score + 0.01
        else:
            self.score = self.score - 0.05
            
        if self.score > 1.0:
            self.score = 1.0
        if self.score < 0.0:
            self.score = 0.0
            
    proc to_dict():
        let d = {}
        d["address"] = self.address
        d["score"] = self.score
        d["uptime"] = self.uptime
        d["mined"] = self.total_blocks_mined
        return d
