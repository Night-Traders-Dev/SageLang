# examples/blockchain_contract_demo.sage

import blockchain.blockchain as bc_mod
import sys

let db_path = "data/contract_test"
sys.exec("rm -rf " + db_path)

print "Initializing Sage Blockchain with Smart Contract Support..."
let my_coin = bc_mod.Blockchain(2, db_path)

print "\nDeploying Counter Contract..."
# This contract increments a 'count' variable stored in its state.
let source = "if not dict_has(state, \"count\"):\n    state[\"count\"] = 0\nstate[\"count\"] = state[\"count\"] + 1\nprint \"Counter Contract: count is now \" + str(state[\"count\"])"
let contract_addr = my_coin.deploy_contract("Alice", source)
print "Contract deployed at: " + contract_addr

print "\nCalling contract (1st time)..."
my_coin.call_contract("Alice", contract_addr, {})
my_coin.mine_pending_transactions("Miner-1")

print "\nCalling contract (2nd time)..."
my_coin.call_contract("Bob", contract_addr, {})
my_coin.mine_pending_transactions("Miner-1")

print "\nContract State:"
let contract = my_coin.contracts[contract_addr]
print "  Final count: " + str(contract.state["count"])

print "\nBlockchain valid? " + str(my_coin.is_chain_valid())
