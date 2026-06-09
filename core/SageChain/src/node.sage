proc main():
    import blockchain.blockchain as bc
    import blockchain.wallet as wallet
    import blockchain.net as net
    import blockchain.rpc as rpc
    import blockchain.consensus.pow as pow_mod
    import thread
    import sys
    import io

    let db_path = "./sagechain_db"
    if not io.exists(db_path):
        print "Initializing new SageChain Database..."

    # Phase 6: Initialize with modular PoW consensus
    let consensus = pow_mod.PowConsensus(nil, 4)
    let chain = bc.Blockchain(consensus, db_path)
    consensus.blockchain = chain

    let w = wallet.Wallet(nil)

    print "================================================="
    print "  SageChain Node Started"
    print "  Miner Address: " + w.get_address()
    print "  Current Block Height: " + str(len(chain.chain))
    print "================================================="

    # Start a P2P Node on port 8333
    let p2p = net.P2PNode(chain, 8333)

    # Start JSON-RPC Server on port 8545
    let rpc_srv = rpc.RPCServer(chain, 8545)

    proc run_network():
        print "P2P Network Task Initializing..."
        thread.spawn(rpc_srv.start)
        thread.spawn(p2p.start)

    proc simulator():
        print "Starting network simulator (mining blocks every ~15 seconds)..."
        while true:
            let last_check = clock()
            while clock() - last_check < 15.0:
                let i = 0
                while i < 1000:
                    i = i + 1
            print "Mining new block..."
            let blk = chain.mine_pending_transactions(w.get_address())
            if blk != nil:
                let tx = chain.add_transaction(w.get_address(), "0x" + str(clock()), 1.5)
                w.sign_transaction(tx)
                chain.add_signed_transaction(tx)
                p2p.broadcast("new_block", blk.to_dict())

    # Use the scheduler to run both tasks
    run_network()
    simulator()

main()
