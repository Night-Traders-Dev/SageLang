# lib/blockchain/events.sage
# Event Logging System for Sage Blockchain

import io
import json

class EventLog:
    proc init(db_path):
        self.path = db_path
        self.events = {} # In-memory cache of events by contract
        
    proc emit(contract_addr, event_name, data):
        let event = {
            "contract": contract_addr,
            "name": event_name,
            "data": data,
            "timestamp": clock()
        }
        
        # Cache for quick access
        if not dict_has(self.events, contract_addr):
            self.events[contract_addr] = []
        push(self.events[contract_addr], event)
        
        # Log to disk
        let cjson = json.cJSON_FromSage(event)
        let log_line = json.cJSON_PrintUnformatted(cjson) + "\n"
        json.cJSON_Delete(cjson)
        io.appendfile(self.path, log_line)
        print "EVENT [" + event_name + "] from " + contract_addr

    proc query(contract_addr, event_name):
        let logs = []
        # Return from cache
        if dict_has(self.events, contract_addr):
            for e in self.events[contract_addr]:
                if e["name"] == event_name:
                    push(logs, e)
        return logs
