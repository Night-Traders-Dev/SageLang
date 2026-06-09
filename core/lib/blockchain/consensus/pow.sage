# lib/blockchain/consensus/pow.sage

from blockchain.consensus.base import Consensus
import blockchain.block as block_mod

class PowConsensus(Consensus):
    proc init(blockchain, difficulty):
        self.blockchain = blockchain
        self.difficulty = difficulty

    proc validate_block(block):
        let target = ""
        let i = 0
        while i < self.difficulty:
            target = target + "0"
            i = i + 1
        
        if not startswith(block.hash, target):
            print "PoW Error: Block hash does not meet difficulty"
            return false
        return true

    proc seal_block(transactions, miner_address):
        let block_height = len(self.blockchain.chain)
        let prev_hash = "0"
        if block_height > 0:
            prev_hash = self.blockchain.chain[block_height - 1].hash
            
        let block = block_mod.Block(block_height, transactions, prev_hash, self.difficulty)
        block.mine()
        return block
