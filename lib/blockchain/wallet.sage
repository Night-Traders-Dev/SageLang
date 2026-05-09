# lib/blockchain/wallet.sage

import crypto.rand as rand

class Wallet:
    proc init():
        # Seed with current clock to get some randomness
        let rng = rand.lcg_create(clock() * 10000)
        
        let digits = "0123456789abcdef"
        
        # Generate private key (32 bytes)
        let pk = ""
        let i = 0
        while i < 32:
            let b = rand.lcg_bounded(rng, 256)
            pk = pk + digits[(b >> 4) & 15] + digits[b & 15]
            i = i + 1
        self.private_key = pk
        
        # Generate address (20 bytes)
        let addr = "0x"
        let j = 0
        while j < 20:
            let b = rand.lcg_bounded(rng, 256)
            addr = addr + digits[(b >> 4) & 15] + digits[b & 15]
            j = j + 1
        self.address = addr

    proc get_address():
        return self.address

    proc sign_transaction(tx):
        # In a real blockchain, we would use asymmetric crypto here.
        # For this demo, we'll just "sign" by adding a signature field 
        # that is a hash of the transaction and the private key.
        import crypto.hash as hash
        let data = str(tx.to_dict()) + self.private_key
        tx.signature = hash.sha256_hex(data)
        return tx.signature
