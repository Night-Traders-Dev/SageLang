# lib/blockchain/transaction.sage

class Transaction:
    proc init(sender, receiver, amount):
        self.sender = sender
        self.receiver = receiver
        self.amount = amount
        self.timestamp = clock()
        self.signature = nil

    proc to_dict():
        let d = {}
        d["sender"] = self.sender
        d["receiver"] = self.receiver
        d["amount"] = self.amount
        d["timestamp"] = self.timestamp
        d["signature"] = self.signature
        return d

    proc to_string():
        return "Tx(from=" + str(self.sender) + ", to=" + str(self.receiver) + ", amt=" + str(self.amount) + ")"

    proc calculate_hash():
        import crypto.hash as hash
        let data = str(self.sender) + str(self.receiver) + str(self.amount) + str(self.timestamp)
        return hash.sha256_hex(data)
