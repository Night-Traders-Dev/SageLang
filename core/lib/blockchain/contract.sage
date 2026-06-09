# lib/blockchain/contract.sage

import vm

class Contract:
    proc init(source):
        self.source = source
        let ptr = vm.compile(source)
        if ptr == nil:
            print "Contract compilation failed!"
            self.bytecode = nil
        else:
            self.bytecode = vm.serialize(ptr)
        self.state = {}

    proc execute(args, context, call_stack):
        let ptr = vm.deserialize(self.bytecode)
        if ptr == nil:
            return nil
            
        # Check payable status
        if context["value"] > 0 and not dict_has(self.state, "payable"):
            print "Contract Error: Not payable"
            return nil
            
        # Merge args and context into state
        if type(args) == "dict":
            let keys = dict_keys(args)
            for k in keys:
                self.state[k] = args[k]
        
        if type(context) == "dict":
            let keys = dict_keys(context)
            for k in keys:
                self.state[k] = context[k]
            
        # Attach call_stack to execution context
        if call_stack == nil:
            call_stack = []
        self.state["call_stack"] = call_stack
        
        self.state["now"] = clock()
        
        # Ensure 'storage' mapping is available
        if not dict_has(self.state, "storage"):
            self.state["storage"] = {}
        
        # Gas Budgeting
        let start_gas = vm_gas_used_get()
        
        print "VM executing..."
        let env = {"state": self.state}
        let res = vm.execute(ptr, env)
        
        # Deduct gas based on execution
        let end_gas = vm_gas_used_get()
        if end_gas > vm_gas_limit_get():
            print "Contract Error: Out of gas"
            return nil

        print "VM execution complete."
        return res

    proc to_dict():
        let d = {}
        d["source"] = self.source
        d["bytecode"] = self.bytecode
        d["state"] = self.state
        return d
