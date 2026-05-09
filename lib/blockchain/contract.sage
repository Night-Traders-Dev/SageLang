# lib/blockchain/contract.sage

import vm

class Contract:
    proc init(source):
        self.source = source
        let ptr = vm.compile(source)
        if ptr == nil:
            print "Contract compilation failed!"
            return
        self.bytecode = vm.serialize(ptr)
        self.state = {}

    proc execute(args):
        let ptr = vm.deserialize(self.bytecode)
        if ptr == nil:
            print "Contract deserialization failed!"
            return nil
        
        # Merge args into state
        if type(args) == "dict":
            let keys = dict_keys(args)
            for k in keys:
                self.state[k] = args[k]
        
        return vm.execute(ptr, self.state)

    proc to_dict():
        let d = {}
        d["source"] = self.source
        d["bytecode"] = self.bytecode
        d["state"] = self.state
        return d
