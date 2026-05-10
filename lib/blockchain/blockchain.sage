# lib/blockchain/blockchain.sage

import blockchain.block as block_mod
import blockchain.transaction as tx_mod
import blockchain.contract as contract_mod
import blockchain.orbit as orbit
import blockchain.node as node_mod
import blockchain.db as db_mod
import blockchain.crypto as crypto # Phase 1
import blockchain.merkle as merkle # Phase 3
import blockchain.net as p2p    # Phase 4
import blockchain.events as event_mod # Phase 5
import thread

class Blockchain:
    proc init(consensus_or_diff, db_path):
        self.chain = []
        self.mempool = []
        self.contracts = {}
        self.nodes = {}
        
        # Phase 6: Support for both modular consensus and legacy difficulty
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
        self.events = event_mod.EventLog(db_path + "/events.log") # Phase 5
        self.state_trie = merkle.StateTrie() # Phase 1: Global World State
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
            let diff = 0
            if dict_has(block_dict, "difficulty"):
                diff = block_dict["difficulty"]
            let block = block_mod.Block(block_dict["index"], block_dict["transactions"], block_dict["previous_hash"], diff)
            block.timestamp = block_dict["timestamp"]
            block.nonce = block_dict["nonce"]
            block.hash = block_dict["hash"]
            if dict_has(block_dict, "state_root"):
                block.state_root = block_dict["state_root"] # Phase 3
            
            push(self.chain, block)
            self.last_block_time = block.timestamp
            
            # Track total mined and populate StateTrie
            if type(block.transactions) == "array":
                for tx in block.transactions:
                    if type(tx) == "dict":
                        if tx["sender"] == "System":
                            self.total_mined = self.total_mined + tx["amount"]
                        
                        # Populate StateTrie with final balances
                        if dict_has(tx, "sender"):
                            let s_bal = self.get_balance(tx["sender"])
                            self.state_trie.update(tx["sender"], {"balance": s_bal})
                        if dict_has(tx, "receiver"):
                            let r_bal = self.get_balance(tx["receiver"])
                            self.state_trie.update(tx["receiver"], {"balance": r_bal})
                        
            height = height + 1
        
        if len(self.chain) > 0:
            print "Loaded " + str(len(self.chain)) + " blocks from database."

    async proc create_genesis_block():
        # No lock needed here as it's called during init
        # Using a list for transactions
        let genesis = await self.consensus.seal_block(["Genesis Block"], "System")
        if genesis == nil:
            # Fallback if consensus fails to seal
            genesis = block_mod.Block(0, ["Genesis Block"], "0", 0)
            await genesis.mine()

        # Phase 1: Set initial state root using StateTrie
        genesis.state_root = self.state_trie.get_root_hash()

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

    proc add_block(block_dict):
        # Validate incoming block dictionary
        if block_dict == nil: return
        
        thread.lock(self.mutex)
        let current_height = len(self.chain)
        let incoming_height = block_dict["index"]
        
        if incoming_height == current_height:
            # Reconstruct and validate
            let block = block_mod.Block(block_dict["index"], block_dict["transactions"], block_dict["previous_hash"], block_dict["difficulty"])
            block.timestamp = block_dict["timestamp"]
            block.nonce = block_dict["nonce"]
            block.hash = block_dict["hash"]
            block.state_root = block_dict["state_root"]
            
            # Simple validation: previous hash must match
            if block.previous_hash == self.chain[current_height - 1].hash:
                if self.consensus.validate_block(block):
                    push(self.chain, block)
                    self.last_block_time = block.timestamp
                    # Async save to DB (caller must handle)
                    # We'll rely on the node loop to finalize state later
                    print "✅ Block " + str(incoming_height) + " accepted via P2P"
            
        elif incoming_height > current_height:
            # Fork resolution / Sync: peer is ahead of us
            # In a real chain, we'd request the missing blocks (IBD)
            print "Found peer with longer chain (h=" + str(incoming_height) + "). Syncing..."
        thread.unlock(self.mutex)

    proc add_signed_transaction(tx_dict):
        thread.lock(self.mutex)
        defer thread.unlock(self.mutex)
        if self.is_transaction_valid(tx_dict):
            # Check if tx already in mempool
            for existing in self.mempool:
                if existing["hash"] == tx_dict["hash"]:
                    return true
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
        
        # Update World State Trie with contract metadata
        self.state_trie.update(addr, {"type": "contract", "balance": 0.0, "source_len": len(source)})
        
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
        tx["gas_limit"] = 10000 # Phase 2: Default gas limit
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
        
        # Phase 1: Real signature verification
        let msg = str(tx_dict["sender"]) + str(tx_dict["receiver"]) + str(tx_dict["amount"])
        return crypto.verify(msg, tx_dict["signature"], tx_dict["public_key"])

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
        
        # Phase 3: Priority Fee Market (sort by gas_price DESC)
        # Simple selection sort for SageLang (replace with faster sort later)
        let sorted_mempool = []
        let temp = self.mempool
        while len(temp) > 0:
            let max_idx = 0
            let max_val = -1.0
            for i in range(len(temp)):
                let gp = 0.0
                if dict_has(temp[i], "gas_price"): gp = temp[i]["gas_price"]
                if gp > max_val:
                    max_val = gp
                    max_idx = i
            push(sorted_mempool, temp[max_idx])
            # Manual remove from array
            let next_temp = []
            for i in range(len(temp)):
                if i != max_idx: push(next_temp, temp[i])
            temp = next_temp
            
        let pending = sorted_mempool
        self.mempool = []
        thread.unlock(self.mutex)

        let state_data = []
        let total_fees = 0.0

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
                
                # Update World State Trie
                self.state_trie.update(tx["sender"], {"balance": sender_bal - tx["amount"]})
                self.state_trie.update(tx["receiver"], {"balance": receiver_bal + tx["amount"]})
                
                push(state_data, tx["sender"] + ":" + str(sender_bal - tx["amount"]))
            
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
                        
                        # Phase 2: Gas Metering
                        vm_set_gas_limit(tx["gas_limit"])
                        let results = contract.execute(tx["args"], context)
                        let gas_used = vm_get_gas_used()
                        print "Contract gas used: " + str(gas_used)
                        
                        # Phase 3: Fees
                        let fee = gas_used * 0.001 # Assume 0.001 ORBIT per gas unit base
                        if dict_has(tx, "gas_price"): fee = gas_used * tx["gas_price"]
                        total_fees = total_fees + fee
                        
                        # Handle contract results (outgoing transfers)
                        if type(results) == "array":
                            for transfer in results:
                                if type(transfer) == "dict" and dict_has(transfer, "to") and dict_has(transfer, "amount"):
                                    let c_bal = self.get_balance(addr)
                                    let r_bal = self.get_balance(transfer["to"])
                                    if c_bal >= transfer["amount"]:
                                        await self.db.save_account_balance(addr, c_bal - transfer["amount"])
                                        await self.db.save_account_balance(transfer["to"], r_bal + transfer["amount"])
                                        
                                        # Update World State Trie
                                        self.state_trie.update(addr, {"balance": c_bal - transfer["amount"]})
                                        self.state_trie.update(transfer["to"], {"balance": r_bal + transfer["amount"]})
                                        
                                        # Index the internal transfer
                                        import crypto.hash as hash
                                        let v_tx = {"sender": addr, "receiver": transfer["to"], "amount": transfer["amount"], "timestamp": clock(), "type": "contract_transfer"}
                                        v_tx["hash"] = hash.sha256_hex(str(v_tx) + str(clock()))
                                        await self.db.save_transaction(v_tx)
                                        await self.db.append_tx_to_history(addr, v_tx["hash"])
                                        await self.db.append_tx_to_history(transfer["to"], v_tx["hash"])
                                        
                                        # Phase 5: Emit Transfer Event
                                        await self.events.emit(addr, "Transfer", transfer)

                        # Persist updated contract state
                        await self.db.save_contract_state(addr, contract.to_dict())
                        
                        # Update World State Trie with latest balance and some state metadata
                        let final_c_bal = self.get_balance(addr)
                        self.state_trie.update(addr, {"type": "contract", "balance": final_c_bal, "state_keys": len(dict_keys(contract.state))})
        
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
            
        let reward = (rate * time_elapsed) + total_fees
        print "Mining Reward: " + str(reward) + " ORBIT (Rate: " + str(rate) + ", Fees: " + str(total_fees) + ")"
        
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
        
        # Update World State Trie
        self.state_trie.update(miner_address, {"balance": miner_bal + reward})
        
        let prev_hash = self.chain[len(self.chain) - 1].hash
        thread.unlock(self.mutex)

        # Include reward in block transactions
        push(pending, reward_dict)
        
        # Phase 6: Use pluggable consensus to seal the block
        let block = await self.consensus.seal_block(pending, miner_address)
        if block == nil:
            print "Consensus failed to seal block"
            return nil
        
        # Phase 1 Upgrade: Use StateTrie root instead of simple Merkle tree
        block.state_root = self.state_trie.get_root_hash()
        
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
            
            # Phase 6: Use pluggable consensus to validate block rules
            if not self.consensus.validate_block(current):
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
