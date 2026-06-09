# lib/blockchain/consensus/base.sage

class Consensus:
    proc init(blockchain):
        self.blockchain = blockchain

    proc validate_block(block):
        # To be implemented by subclasses
        return false

    proc seal_block(transactions, miner_address):
        # To be implemented by subclasses
        return nil
