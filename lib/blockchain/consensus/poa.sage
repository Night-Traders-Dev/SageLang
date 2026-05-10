# lib/blockchain/consensus/poa.sage

from blockchain.consensus.base import Consensus
import blockchain.block as block_mod
import blockchain.crypto as bc_crypto

class PoAConsensus(Consensus):
    proc init(blockchain, authorities):
        self.blockchain = blockchain
        self.authorities = authorities # List of authorized public keys
        self.slashed = {} # Track slashed authorities

    proc validate_block(block):
        # In PoA, we check if the block is signed by an authority
        if not dict_has(block, "signature"):
            print "PoA Error: Block missing signature"
            return false
            
        let signer = block["signer"]
        
        # Check if signer is slashed
        if dict_has(self.slashed, signer):
            print "PoA Error: Signer " + signer + " has been slashed!"
            return false

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

    proc seal_block(transactions, miner_address):
        # Check if miner is an authority
        if dict_has(self.slashed, miner_address):
            print "PoA Error: Miner is slashed"
            return nil

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
        
        # Automatic Slashing for Equivocation (Double Signing)
        # In a real network, this would check if another block exists at this height
        # signed by the same miner. For simulation, we check local chain.
        for b in self.blockchain.chain:
            if b.index == block_height and dict_has(b, "signer") and b["signer"] == miner_address:
                print "Equivocation detected! Slashing " + miner_address
                self.slash(miner_address)
                return nil

        return block

    proc slash(address):
        self.slashed[address] = true
        # Remove from authorities
        let new_auths = []
        for a in self.authorities:
            if a != address:
                push(new_auths, a)
        self.authorities = new_auths

    proc add_authority(address):
        # Validator Rotation / Governance
        for a in self.authorities:
            if a == address:
                return
        push(self.authorities, address)

    proc remove_authority(address):
        let new_auths = []
        for a in self.authorities:
            if a != address:
                push(new_auths, a)
        self.authorities = new_auths
