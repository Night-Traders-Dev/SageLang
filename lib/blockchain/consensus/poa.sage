# lib/blockchain/consensus/poa.sage

from blockchain.consensus.base import Consensus
import blockchain.block as block_mod
import blockchain.crypto as crypto

class PoAConsensus(Consensus):
    proc init(blockchain, authorities):
        self.blockchain = blockchain
        self.authorities = authorities # List of authorized public keys

    proc validate_block(block):
        # In PoA, we check if the block is signed by an authority
        if not dict_has(block, "signature"):
            print "PoA Error: Block missing signature"
            return false
            
        let signer = block["signer"]
        let is_auth = false
        for auth in self.authorities:
            if auth == signer:
                is_auth = true
                break
        
        if not is_auth:
            print "PoA Error: Signer " + signer + " is not an authority"
            return false
            
        # Verify signature of the block hash
        return crypto.verify(block.hash, block["signature"], signer)

    async proc seal_block(transactions, miner_address):
        # Check if miner is an authority
        let is_auth = false
        for auth in self.authorities:
            if auth == miner_address:
                is_auth = true
                break
        
        if not is_auth:
            print "PoA Error: Miner is not an authority"
            return nil

        let block_height = len(self.blockchain.chain)
        let prev_hash = "0"
        if block_height > 0:
            prev_hash = self.blockchain.chain[block_height - 1].hash
            
        let block = block_mod.Block(block_height, transactions, prev_hash, 0)
        # In PoA, difficulty is 0, no mining needed
        # But we need to sign it. This requires the authority's private key.
        # For simulation, we'll assume the blockchain provides a sign method or similar.
        
        return block
