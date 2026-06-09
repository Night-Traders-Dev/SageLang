# lib/blockchain/transaction.sage

class Transaction:
    proc init(sender, receiver, amount, nonce, chain_id):
        self.sender = sender
        self.receiver = receiver
        self.amount = amount
        self.gas_price = 10.0
        self.nonce = nonce
        self.chain_id = chain_id
        self.timestamp = clock()
        self.signature = nil
        self.public_key = nil

    proc to_dict():
        let d = {}
        d["sender"] = self.sender
        d["receiver"] = self.receiver
        d["amount"] = self.amount
        d["gas_price"] = self.gas_price
        d["nonce"] = self.nonce
        d["chain_id"] = self.chain_id
        d["timestamp"] = self.timestamp
        d["signature"] = self.signature
        d["public_key"] = self.public_key
        return d

    proc to_string():
        return "Tx(from=" + str(self.sender) + ", to=" + str(self.receiver) + ", amt=" + str(self.amount) + ", nonce=" + str(self.nonce) + ")"

    proc calculate_hash():
        import crypto.hash as hash
        # Include nonce and chain_id to prevent replay and cross-chain attacks
        let data = str(self.sender) + ":" + str(self.receiver) + ":" + str(self.amount) + ":" + str(self.gas_price) + ":" + str(self.nonce) + ":" + str(self.chain_id) + ":" + str(self.timestamp)
        return hash.sha256_hex(data)
