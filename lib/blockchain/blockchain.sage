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

    proc add_transaction(sender, receiver, amount):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        let tx = tx_mod.Transaction(sender, receiver, amount)
        let tx_dict = tx.to_dict()
        tx_dict["hash"] = tx.calculate_hash()
        push(self.mempool, tx_dict)
        return tx

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
        for tx in pending:
            self.db.save_transaction(tx)
            
            # Standard transfer
            if not dict_has(tx, "type"):
                let s_bal = self.db.get_account_balance(tx["sender"])
                let r_bal = self.db.get_account_balance(tx["receiver"])
                if s_bal >= tx["amount"]:
                    self.db.save_account_balance(tx["sender"], s_bal - tx["amount"])
                    self.db.save_account_balance(tx["receiver"], r_bal + tx["amount"])
                    # self.state_trie.update(tx["sender"], {"balance": s_bal - tx["amount"]})
                    # self.state_trie.update(tx["receiver"], {"balance": r_bal + tx["amount"]})
            
            # Contract interactions
            if dict_has(tx, "type"):
                if tx["type"] == "call":
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
                        let context = {"sender": tx["sender"], "value": tx["amount"]}
                        
                        # Gas metering
                        vm_gas_limit_set(tx["gas_limit"])
                        let res = contract.execute(tx["args"], context)
                        let used = vm_gas_used_get()
                        
                        let gp = 0.0
                        if dict_has(tx, "gas_price"):
                            gp = tx["gas_price"]
                        total_fees = total_fees + (used * gp * 0.001)
                        
                        # Internal transfers
                        if type(res) == "array":
                            for t in res:
                                if type(t) == "dict" and dict_has(t, "to") and dict_has(t, "amount"):
                                    let cb = self.db.get_account_balance(addr)
                                    let rb = self.db.get_account_balance(t["to"])
                                    if cb >= t["amount"]:
                                        self.db.save_account_balance(addr, cb - t["amount"])
                                        self.db.save_account_balance(t["to"], rb + t["amount"])
                                        # self.state_trie.update(addr, {"balance": cb - t["amount"]})
                                        # self.state_trie.update(t["to"], {"balance": rb + t["amount"]})

                        self.db.save_contract_state(addr, contract.to_dict())
                        let final_b = self.db.get_account_balance(addr)
                        # self.state_trie.update(addr, {"type": "contract", "balance": final_b})

        # Miner reward
        let reward = 10.0 + total_fees
        let miner_b = self.db.get_account_balance(miner_address)
        self.db.save_account_balance(miner_address, miner_b + reward)
        # self.state_trie.update(miner_address, {"balance": miner_b + reward})
        
        let block = self.consensus.seal_block(pending, miner_address)
        if block != nil:
            block.state_root = "0x"
            thread.lock(self.mutex)
            push(self.chain, block)
            self.last_block_time = block.timestamp
            self.db.save_block(block)
            thread.unlock(self.mutex)
            
        return block

    proc get_balance(address):
        return self.db.get_account_balance(address)
