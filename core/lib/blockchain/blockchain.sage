# lib/blockchain/blockchain.sage

import blockchain.block as block_mod
import blockchain.transaction as tx_mod
import blockchain.contract as contract_mod
import blockchain.orbit as orbit
import blockchain.node as node_mod
import blockchain.db as db_mod
import blockchain.crypto as bc_crypto
import blockchain.merkle as merkle
import blockchain.net as p2p
import blockchain.events as event_mod
import thread
import crypto.hash as hash

class Blockchain:
    proc init(consensus_or_diff, db_path):
        self.chain = []
        self.mempool = []
        self.contracts = {}
        self.nodes = {}
        self.consensus = nil
        
        if type(consensus_or_diff) == "number":
            import blockchain.consensus.pow as pow_mod
            self.consensus = pow_mod.PowConsensus(self, consensus_or_diff)
        else:
            self.consensus = consensus_or_diff
            if self.consensus != nil:
                self.consensus.blockchain = self

        self.total_mined = 0.0
        self.last_block_time = clock()
        self.mutex = thread.mutex()
        
        self.db = db_mod.LedgerDB(db_path)
        self.events = event_mod.EventLog(db_path + "/events.log")
        # self.state_trie = merkle.StateTrie()
        self.load_from_db()
        
        if len(self.chain) == 0:
            self.create_genesis_block()

    proc load_from_db():
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        let height = 0
        while true:
            let block_dict = self.db.get_block_by_height(height)
            if block_dict == nil:
                break
            
            let diff = 0
            if dict_has(block_dict, "difficulty"):
                diff = block_dict["difficulty"]
            
            let block = block_mod.Block(block_dict["index"], block_dict["transactions"], block_dict["previous_hash"], diff)
            block.timestamp = block_dict["timestamp"]
            block.nonce = block_dict["nonce"]
            block.hash = block_dict["hash"]
            if dict_has(block_dict, "state_root"):
                block.state_root = block_dict["state_root"]
            
            push(self.chain, block)
            self.last_block_time = block.timestamp
            
            # Update World State from history
            if type(block.transactions) == "array":
                for tx in block.transactions:
                    if type(tx) == "dict":
                        if dict_has(tx, "sender"):
                            if tx["sender"] == "System":
                                self.total_mined = self.total_mined + tx["amount"]
                            
                            let s_bal = self.db.get_account_balance(tx["sender"])
                            # self.state_trie.update(tx["sender"], {"balance": s_bal})
                        if dict_has(tx, "receiver"):
                            let r_bal = self.db.get_account_balance(tx["receiver"])
                            # self.state_trie.update(tx["receiver"], {"balance": r_bal})
            height = height + 1
        
        if len(self.chain) > 0:
            print "Loaded " + str(len(self.chain)) + " blocks from database."

    proc create_genesis_block():
        # No lock needed here as it's called during init
        let genesis = self.consensus.seal_block(["Genesis Block"], "System")
        if genesis == nil:
            genesis = block_mod.Block(0, ["Genesis Block"], "0", 0)
            genesis.mine()

        genesis.state_root = "0x"
        push(self.chain, genesis)
        self.last_block_time = genesis.timestamp
        self.db.save_block(genesis)

    proc get_latest_block():
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        if len(self.chain) == 0:
            return nil
        return self.chain[len(self.chain) - 1]

    proc transaction_message(tx):
        let sender = ""
        let receiver = ""
        let amount = 0.0
        let nonce = 0
        let chain_id = 0
        let tx_type = "transfer"
        let timestamp = 0

        if type(tx) == "dict":
            if dict_has(tx, "sender"):
                sender = tx["sender"]
            if dict_has(tx, "receiver"):
                receiver = tx["receiver"]
            if dict_has(tx, "amount"):
                amount = tx["amount"]
            if dict_has(tx, "nonce"):
                nonce = tx["nonce"]
            if dict_has(tx, "chain_id"):
                chain_id = tx["chain_id"]
            if dict_has(tx, "type"):
                tx_type = tx["type"]
            if dict_has(tx, "timestamp"):
                timestamp = tx["timestamp"]
        else:
            sender = tx.sender
            receiver = tx.receiver
            amount = tx.amount
            nonce = tx.nonce
            chain_id = tx.chain_id
            if dict_has(tx, "type"):
                tx_type = tx["type"]
            timestamp = tx.timestamp

        return str(sender) + ":" + str(receiver) + ":" + str(amount) + ":" + str(nonce) + ":" + str(chain_id) + ":" + str(tx_type) + ":" + str(timestamp)

    proc verify_transaction(tx_dict):
        if type(tx_dict) != "dict" and hasattr(tx_dict, "to_dict"):
            tx_dict = tx_dict.to_dict()

        if tx_dict == nil or not dict_has(tx_dict, "sender"):
            return false
        if tx_dict["sender"] == "System":
            return true

        if dict_has(tx_dict, "type") and (tx_dict["type"] == "deploy" or tx_dict["type"] == "call"):
            return true

        if not dict_has(tx_dict, "signature") or not dict_has(tx_dict, "public_key"):
            print "Tx verification failed: missing signature or public_key"
            return false

        let derived = "0x" + hash.sha256_hex(tx_dict["public_key"])[:40]
        if derived != tx_dict["sender"]:
            print "Tx verification failed: public key does not match sender"
            return false

        let msg = self.transaction_message(tx_dict)
        if not bc_crypto.verify(msg, tx_dict["signature"], tx_dict["public_key"]):
            print "Tx verification failed: invalid signature"
            return false

        return true

    proc add_transaction(sender, receiver, amount):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        let tx = tx_mod.Transaction(sender, receiver, amount, 0, 1)
        return tx

    proc add_signed_transaction(tx_dict):
        if type(tx_dict) != "dict" and hasattr(tx_dict, "to_dict"):
            tx_dict = tx_dict.to_dict()

        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)

        if not self.verify_transaction(tx_dict):
            print "Rejected transaction: invalid signature or malformed transaction"
            return false

        if dict_has(tx_dict, "hash") and self.db.get_transaction(tx_dict["hash"]) != nil:
            print "Rejected transaction: duplicate hash"
            return false

        push(self.mempool, tx_dict)
        return true

    proc deploy_contract(sender, source):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        let contract = contract_mod.Contract(source)
        let addr = "0x" + hash.sha256_hex(source + str(clock()))[:40]
        self.contracts[addr] = contract
        
        # self.state_trie.update(addr, {"type": "contract", "balance": 0.0})
        
        let tx = {
            "sender": sender, 
            "type": "deploy", 
            "contract_address": addr, 
            "source": source, 
            "timestamp": clock(), 
            "gas_limit": 50000, 
            "gas_price": 10.0
        }
        tx["hash"] = hash.sha256_hex(str(tx) + str(clock()))
        push(self.mempool, tx)
        return addr

    proc call_contract(sender, addr, args, amount):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        
        let tx = {
            "sender": sender, 
            "type": "call", 
            "contract_address": addr, 
            "args": args, 
            "amount": amount, 
            "gas_limit": 20000, 
            "gas_price": 10.0, 
            "timestamp": clock()
        }
        tx["hash"] = hash.sha256_hex(str(tx) + str(clock()))
        push(self.mempool, tx)
        return true

    proc mine_pending_transactions(miner_address):
        thread.lock(self.mutex)
        let pending = self.mempool
        self.mempool = []
        thread.unlock(self.mutex)

        let total_fees = 0.0
        let valid_txs = []
        for tx_raw in pending:
            let tx = tx_raw
            if type(tx) != "dict":
                tx = tx_raw.to_dict()
            if not dict_has(tx, "hash"):
                tx["hash"] = hash.sha256_hex(str(tx) + str(clock()))

            let result = self.process_transaction(tx)
            if result["valid"]:
                total_fees = total_fees + result["fees"]
                push(valid_txs, tx)
            else:
                print "Dropped invalid transaction during mining: " + tx["hash"]

        let reward = 10.0 + total_fees
        let miner_b = self.db.get_account_balance(miner_address)
        self.db.save_account_balance(miner_address, miner_b + reward)

        let block = self.consensus.seal_block(valid_txs, miner_address)
        if block != nil:
            block.state_root = "0x"
            thread.lock(self.mutex)
            push(self.chain, block)
            self.last_block_time = block.timestamp
            self.db.save_block(block)
            thread.unlock(self.mutex)
            return block
        return nil

    proc get_balance(address):
        return self.db.get_account_balance(address)

    proc register_node(address):
        if not dict_has(self.nodes, address):
            self.nodes[address] = node_mod.Node(address)
            print "Node registered: " + address

    proc get_active_user_count():
        # Count unique addresses in the accounts directory
        let accounts = io.listdir(self.db.account_dir)
        return len(accounts)

    proc process_transaction(tx):
        if tx == nil:
            return {"valid": false, "fees": 0.0}

        if dict_has(tx, "sender") and tx["sender"] != "System":
            if not self.verify_transaction(tx):
                return {"valid": false, "fees": 0.0}

        if not dict_has(tx, "hash"):
            tx["hash"] = hash.sha256_hex(str(tx) + str(clock()))

        if self.db.get_transaction(tx["hash"]) != nil:
            return {"valid": false, "fees": 0.0}

        let fees = 0.0
        let sender = ""
        if dict_has(tx, "sender"):
            sender = tx["sender"]
        let receiver = nil
        if dict_has(tx, "receiver"):
            receiver = tx["receiver"]

        if dict_has(tx, "sender"):
            self.db.append_tx_to_history(tx["sender"], tx["hash"])
        if receiver != nil:
            self.db.append_tx_to_history(receiver, tx["hash"])
        if dict_has(tx, "contract_address"):
            self.db.append_tx_to_history(tx["contract_address"], tx["hash"])

        if not dict_has(tx, "type"):
            if sender != "" and receiver != nil and dict_has(tx, "amount"):
                let s_bal = self.db.get_account_balance(sender)
                let r_bal = self.db.get_account_balance(receiver)
                if s_bal >= tx["amount"]:
                    self.db.save_account_balance(sender, s_bal - tx["amount"])
                    self.db.save_account_balance(receiver, r_bal + tx["amount"])
                else:
                    print "Invalid transfer: insufficient funds for " + sender
                    return {"valid": false, "fees": 0.0}
        else:
            if tx["type"] == "deploy":
                let addr = tx["contract_address"]
                let contract = contract_mod.Contract(tx["source"])
                self.contracts[addr] = contract
                self.db.save_contract_state(addr, contract.to_dict())
            elif tx["type"] == "call":
                let addr = tx["contract_address"]
                if not dict_has(self.contracts, addr):
                    let c_dict = self.db.get_contract_state(addr)
                    if len(dict_keys(c_dict)) > 0:
                        let c = contract_mod.Contract(c_dict["source"])
                        if dict_has(c_dict, "bytecode"):
                            c.bytecode = c_dict["bytecode"]
                        c.state = c_dict["state"]
                        self.contracts[addr] = c

                if dict_has(self.contracts, addr):
                    let contract = self.contracts[addr]
                    let context = {"sender": sender, "value": tx["amount"]}
                    vm_gas_limit_set(tx["gas_limit"])
                    let res = contract.execute(tx["args"], context)
                    let used = vm_gas_used_get()
                    if used == nil:
                        used = 0
                    let gp = 0.0
                    if dict_has(tx, "gas_price"):
                        gp = tx["gas_price"]
                    fees = used * gp * 0.001
                    if type(res) == "array":
                        for t in res:
                            if type(t) == "dict" and dict_has(t, "to") and dict_has(t, "amount"):
                                let cb = self.db.get_account_balance(addr)
                                let rb = self.db.get_account_balance(t["to"])
                                if cb >= t["amount"]:
                                    self.db.save_account_balance(addr, cb - t["amount"])
                                    self.db.save_account_balance(t["to"], rb + t["amount"])
                    self.db.save_contract_state(addr, contract.to_dict())
                else:
                    print "Contract call failed: contract not found " + addr
                    return {"valid": false, "fees": 0.0}

        self.db.save_transaction(tx)
        return {"valid": true, "fees": fees}

    proc add_block(block_dict):
        if block_dict == nil:
            return false

        let block = self.to_block(block_dict)
        if block == nil:
            return false

        let latest = self.get_latest_block()
        if latest != nil and block.previous_hash != latest.hash:
            print "Block rejected: previous hash mismatch"
            return false

        if not self.consensus.validate_block(block):
            print "Block rejected: invalid consensus"
            return false

        if type(block.transactions) == "array":
            for tx in block.transactions:
                if not self.process_transaction(tx)["valid"]:
                    print "Block rejected: invalid transaction in block"
                    return false

        thread.lock(self.mutex)
        push(self.chain, block)
        self.last_block_time = block.timestamp
        self.db.save_block(block)
        thread.unlock(self.mutex)
        return true

    proc to_block(block_dict):
        if block_dict == nil:
            return nil

        let diff = 0
        if dict_has(block_dict, "difficulty"):
            diff = block_dict["difficulty"]

        let block = block_mod.Block(block_dict["index"], block_dict["transactions"], block_dict["previous_hash"], diff)
        if dict_has(block_dict, "timestamp"):
            block.timestamp = block_dict["timestamp"]
        if dict_has(block_dict, "nonce"):
            block.nonce = block_dict["nonce"]
        if dict_has(block_dict, "hash"):
            block.hash = block_dict["hash"]
        if dict_has(block_dict, "state_root"):
            block.state_root = block_dict["state_root"]
        return block

    proc is_chain_valid():
        if len(self.chain) == 0:
            return true

        for i in range(len(self.chain)):
            let block = self.chain[i]
            if block.hash != block.calculate_hash():
                print "Chain invalid: block hash mismatch at height " + str(block.index)
                return false
            if i > 0:
                let prev = self.chain[i - 1]
                if block.previous_hash != prev.hash:
                    print "Chain invalid: bad previous hash at height " + str(block.index)
                    return false
            if not self.consensus.validate_block(block):
                print "Chain invalid: consensus check failed at height " + str(block.index)
                return false

        return true

    proc get_block_by_hash(hash_value):
        return self.db.get_block_by_hash(hash_value)

    proc get_transaction_by_hash(tx_hash):
        return self.db.get_transaction(tx_hash)

    proc get_block_by_height(height):
        return self.db.get_block_by_height(height)

    proc get_transaction_history(address):
        let hashes = self.db.get_tx_history(address)
        let results = []
        for h in hashes:
            let tx = self.db.get_transaction(h)
            if tx != nil:
                push(results, tx)
        return results
