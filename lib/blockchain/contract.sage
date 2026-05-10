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

    proc execute(args, context):
        let ptr = vm.deserialize(self.bytecode)
        if ptr == nil:
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
        
        self.state["now"] = clock()
        
        print "VM executing..."
        let res = vm.execute(ptr, self.state)
        print "VM execution complete."
        return res

    proc to_dict():
        let d = {}
        d["source"] = self.source
        d["bytecode"] = self.bytecode
        d["state"] = self.state
        return d
