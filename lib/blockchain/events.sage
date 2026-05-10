# lib/blockchain/events.sage
# Event Logging System for Sage Blockchain (Phase 5)

import io
import json

class EventLog:
    proc init(db_path):
        self.path = db_path
        
    async proc emit(contract_addr, event_name, data):
        let event = {
            "contract": contract_addr,
            "name": event_name,
            "data": data,
            "timestamp": clock()
        }
        let log_line = json.stringify(event) + "\n"
        await io.appendfile(self.path, log_line)
        print "EVENT [" + event_name + "] from " + contract_addr

    proc query(contract_addr, event_name):
        let logs = []
        if not io.exists(self.path):
            return logs
        
        let lines = split(io.readfile(self.path), "\n")
        for line in lines:
            if len(line) > 0:
                let event = json.parse(line)
                if event["contract"] == contract_addr and event["name"] == event_name:
                    push(logs, event)
        return logs
