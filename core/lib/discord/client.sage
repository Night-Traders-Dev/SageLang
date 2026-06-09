import json
import gateway
import types
import rest

class Client:
    proc init(self, token, intents):
        self.token = token
        self.intents = intents
        self.http = rest.RESTClient(token)
        # Using a simple list or object properties if dict fails
        self.h_keys = []
        self.h_vals = []

    proc on(self, event, handler):
        push(self.h_keys, event)
        push(self.h_vals, handler)

    proc handle_message(self, msg):
        let payload = json.decode(msg)
        let op = payload["op"]
        if op == types.OP_HELLO:
            print("Received HELLO")
        elif op == types.OP_DISPATCH:
            let event = payload["t"]
            let i = 0
            while i < len(self.h_keys):
                if self.h_keys[i] == event:
                    self.h_vals[i](payload["d"])
                i = i + 1

    proc run(self):
        print("Connecting to Discord Gateway...")
