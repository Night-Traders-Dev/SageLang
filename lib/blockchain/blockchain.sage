# lib/blockchain/blockchain.sage

import blockchain.block as block_mod
import blockchain.transaction as tx_mod
import blockchain.contract as contract_mod
import blockchain.orbit as orbit
import blockchain.node as node_mod
import blockchain.db as db_mod
import thread

class Blockchain:
    proc init(difficulty, db_path):
        self.chain = []
        self.mempool = []
        self.contracts = {}
        self.nodes = {}
        self.difficulty = difficulty
        self.total_mined = 0.0
        self.last_block_time = clock()
        self.mutex = thread.mutex()
        
        self.db = db_mod.LedgerDB(db_path)
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
            
            # Reconstruct Block object
            let block = block_mod.Block(block_dict["index"], block_dict["transactions"], block_dict["previous_hash"], block_dict["difficulty"])
            block.timestamp = block_dict["timestamp"]
            block.nonce = block_dict["nonce"]
            block.hash = block_dict["hash"]
            
            push(self.chain, block)
            self.last_block_time = block.timestamp
            
            # Track total mined (sum of system rewards)
            if type(block.transactions) == "array":
                for tx in block.transactions:
                    if type(tx) == "dict" and tx["sender"] == "System":
                        self.total_mined = self.total_mined + tx["amount"]
                        
            height = height + 1
        
        if len(self.chain) > 0:
            print "Loaded " + str(len(self.chain)) + " blocks from database."

    proc create_genesis_block():
        # No lock needed here as it's called during init
        # Using a list for transactions
        let genesis = block_mod.Block(0, ["Genesis Block"], "0", self.difficulty)
        await genesis.mine()
        push(self.chain, genesis)
        self.last_block_time = genesis.timestamp
        await self.db.save_block(genesis)

    proc get_latest_block():
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        return self.chain[len(self.chain) - 1]

    proc register_node(address):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        if not dict_has(self.nodes, address):
            self.nodes[address] = node_mod.Node(address)
        return self.nodes[address]

    proc add_transaction(sender, receiver, amount):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        let tx = tx_mod.Transaction(sender, receiver, amount)
        let tx_dict = tx.to_dict()
        tx_dict["hash"] = tx.calculate_hash()
        push(self.mempool, tx_dict)
        return tx

    proc add_signed_transaction(tx):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        let tx_dict = tx.to_dict()
        tx_dict["hash"] = tx.calculate_hash()
        if self.is_transaction_valid(tx_dict):
            push(self.mempool, tx_dict)
            return true
        return false

    proc deploy_contract(sender, source):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        # In a real blockchain, this would be a transaction
        let contract = contract_mod.Contract(source)
        # Simple address generation: hash of source + timestamp
        import crypto.hash as hash
        let addr = "0x" + hash.sha256_hex(source + str(clock()))[:40]
        self.contracts[addr] = contract
        
        # Persist contract to DB
        await self.db.save_contract_state(addr, contract.to_dict())
        
        # Add a deployment record to mempool
        let tx = {}
        tx["sender"] = sender
        tx["type"] = "deploy"
        tx["contract_address"] = addr
        tx["source"] = source
        tx["timestamp"] = clock()
        push(self.mempool, tx)
        
        return addr

    proc call_contract(sender, addr, args, amount):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        if not dict_has(self.contracts, addr):
            # Try to load from DB
            let c_dict = self.db.get_contract_state(addr)
            if len(dict_keys(c_dict)) > 0:
                let c = contract_mod.Contract(c_dict["source"])
                c.bytecode = c_dict["bytecode"]
                c.state = c_dict["state"]
                self.contracts[addr] = c
            else:
                print "Contract not found: " + addr
                return nil
            
        # Add a call record to mempool
        let tx = {}
        tx["sender"] = sender
        tx["type"] = "call"
        tx["contract_address"] = addr
        tx["args"] = args
        tx["amount"] = amount # Amount of ORBIT sent to the contract
        tx["timestamp"] = clock()
        push(self.mempool, tx)
        return true

    proc is_transaction_valid(tx_dict):
        if tx_dict["sender"] == "System":
            return true
        # Handle special transaction types
        if dict_has(tx_dict, "type"):
            if tx_dict["type"] == "deploy" or tx_dict["type"] == "call":
                return true
        if tx_dict["signature"] == nil:
            print "Transaction missing signature!"
            return false
        # Placeholder for real signature verification
        return true

    proc get_active_user_count():
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        # Simplified: unique addresses in the chain
        let users = {}
        for block in self.chain:
            if type(block.transactions) == "array":
                for tx in block.transactions:
                    if type(tx) == "dict":
                        if dict_has(tx, "sender"):
                            users[tx["sender"]] = true
                        if dict_has(tx, "receiver"):
                            users[tx["receiver"]] = true
        return len(dict_keys(users))

    async proc mine_pending_transactions(miner_address):
        # We need to be careful with locking here because mining takes time.
        # We should capture the mempool and then unlock so new tx can be added.
        thread.lock(self.mutex)
        let pending = self.mempool
        self.mempool = []
        thread.unlock(self.mutex)

        # Process transactions in local 'pending' copy
        for tx in pending:
            # Ensure transaction has a hash
            if not dict_has(tx, "hash"):
                import crypto.hash as hash
                let data = str(tx) + str(clock())
                tx["hash"] = hash.sha256_hex(data)
            
            # Index transaction
            await self.db.save_transaction(tx)
            await self.db.append_tx_to_history(tx["sender"], tx["hash"])
            if dict_has(tx, "receiver"):
                await self.db.append_tx_to_history(tx["receiver"], tx["hash"])

            # Update balances (if standard transaction)
            if not dict_has(tx, "type"):
                let sender_bal = self.get_balance(tx["sender"])
                let receiver_bal = self.get_balance(tx["receiver"])
                await self.db.save_account_balance(tx["sender"], sender_bal - tx["amount"])
                await self.db.save_account_balance(tx["receiver"], receiver_bal + tx["amount"])
            
            if dict_has(tx, "type"):
                if tx["type"] == "call":
                    let addr = tx["contract_address"]
                    # Get contract under lock
                    thread.lock(self.mutex)
                    let contract = self.contracts[addr]
                    thread.unlock(self.mutex)
                    
                    # Handle incoming transfer to contract
                    let incoming_ok = true
                    if dict_has(tx, "amount") and tx["amount"] > 0:
                        let sender_bal = self.get_balance(tx["sender"])
                        let contract_bal = self.get_balance(addr)
                        if sender_bal >= tx["amount"]:
                            await self.db.save_account_balance(tx["sender"], sender_bal - tx["amount"])
                            await self.db.save_account_balance(addr, contract_bal + tx["amount"])
                        else:
                            print "Insufficient balance for contract call from " + tx["sender"]
                            incoming_ok = false
                    
                    if incoming_ok:
                        print "Executing contract at " + addr
                        let context = {"sender": tx["sender"], "value": tx["amount"]}
                        let results = contract.execute(tx["args"], context)
                        
                        # Handle contract results (outgoing transfers)
                        if type(results) == "array":
                            for transfer in results:
                                if type(transfer) == "dict" and dict_has(transfer, "to") and dict_has(transfer, "amount"):
                                    let c_bal = self.get_balance(addr)
                                    let r_bal = self.get_balance(transfer["to"])
                                    if c_bal >= transfer["amount"]:
                                        await self.db.save_account_balance(addr, c_bal - transfer["amount"])
                                        await self.db.save_account_balance(transfer["to"], r_bal + transfer["amount"])
                                        
                                        # Index the internal transfer
                                        import crypto.hash as hash
                                        let v_tx = {"sender": addr, "receiver": transfer["to"], "amount": transfer["amount"], "timestamp": clock(), "type": "contract_transfer"}
                                        v_tx["hash"] = hash.sha256_hex(str(v_tx) + str(clock()))
                                        await self.db.save_transaction(v_tx)
                                        await self.db.append_tx_to_history(addr, v_tx["hash"])
                                        await self.db.append_tx_to_history(transfer["to"], v_tx["hash"])

                        # Persist updated contract state
                        await self.db.save_contract_state(addr, contract.to_dict())
        
        # Calculate dynamic mining reward using Orbit model
        let node_score = 1.0
        thread.lock(self.mutex)
        if dict_has(self.nodes, miner_address):
            node_score = self.nodes[miner_address].score
        thread.unlock(self.mutex)
        
        let users = self.get_active_user_count()
        let block_height = 0
        thread.lock(self.mutex)
        block_height = len(self.chain)
        thread.unlock(self.mutex)
        
        let rate = orbit.calculate_mining_rate(users, self.total_mined, block_height, node_score)
        
        # Reward = rate * time_elapsed (simplified for demo)
        let now_time = clock()
        let time_elapsed = now_time - self.last_block_time
        if time_elapsed < 1.0:
            time_elapsed = 1.0
            
        let reward = rate * time_elapsed
        print "Mining Reward: " + str(reward) + " ORBIT (Rate: " + str(rate) + ")"
        
        # Add reward for miner (System tx)
        let reward_tx = tx_mod.Transaction("System", miner_address, reward)
        let reward_dict = reward_tx.to_dict()
        reward_dict["hash"] = reward_tx.calculate_hash()
        
        # Index reward tx
        await self.db.save_transaction(reward_dict)
        await self.db.append_tx_to_history("System", reward_dict["hash"])
        await self.db.append_tx_to_history(miner_address, reward_dict["hash"])

        # Update stats under lock
        thread.lock(self.mutex)
        self.total_mined = self.total_mined + reward
        let miner_bal = self.db.get_account_balance(miner_address)
        await self.db.save_account_balance(miner_address, miner_bal + reward)
        
        let prev_hash = self.chain[len(self.chain) - 1].hash
        thread.unlock(self.mutex)

        # Include reward in block transactions
        push(pending, reward_dict)
        
        let block = block_mod.Block(block_height, pending, prev_hash, self.difficulty)
        await block.mine()
        
        # Finalize block under lock
        thread.lock(self.mutex)
        push(self.chain, block)
        self.last_block_time = block.timestamp
        
        # Save to DB
        await self.db.save_block(block)
        
        # Update node stats
        if dict_has(self.nodes, miner_address):
            let n = self.nodes[miner_address]
            n.total_blocks_mined = n.total_blocks_mined + 1
            n.update_score(true)
        thread.unlock(self.mutex)
            
        return block

    proc get_balance(address):
        return self.db.get_account_balance(address)

    proc get_transaction_history(address):
        let hashes = self.db.get_tx_history(address)
        let history = []
        for h in hashes:
            let tx = self.db.get_transaction(h)
            if tx != nil:
                push(history, tx)
        return history

    proc is_chain_valid():
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        let i = 1
        while i < len(self.chain):
            let current = self.chain[i]
            let previous = self.chain[i - 1]
            
            if current.hash != current.calculate_hash():
                print "Invalid hash for block " + str(i)
                return false
            
            if current.previous_hash != previous.hash:
                print "Invalid previous_hash for block " + str(i)
                return false
            
            # Validate transactions in block
            if type(current.transactions) == "array":
                for tx in current.transactions:
                    if type(tx) == "dict":
                        if not self.is_transaction_valid(tx):
                            print "Invalid transaction in block " + str(i)
                            return false
            
            i = i + 1
        return true
