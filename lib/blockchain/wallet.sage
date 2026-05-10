# lib/blockchain/wallet.sage

import blockchain.crypto as crypto

class Wallet:
    proc init():
        let keys = crypto.generate_keypair()
        self.private_key = keys["private"]
        self.public_key = keys["public"]
        self.address = self.public_key # Address is public key (standard frontier style)

    proc get_address():
        return self.address

    proc sign_transaction(tx):
        # Phase 1: Real asymmetric signing
        let msg = str(tx.sender) + str(tx.receiver) + str(tx.amount)
        tx.signature = crypto.sign(msg, self.private_key)
        tx.public_key = self.public_key
        return tx.signature
