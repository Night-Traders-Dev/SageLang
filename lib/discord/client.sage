import net.websocket
import discord.types
import discord.gateway
import discord.rest
import json

class Client:
    proc init(token, intents):
        self.token = token
        self.intents = intents
        self.ws = nil
        self.heartbeat_interval = 0
        self.last_seq = nil
        self.handlers = {}
        self.http = discord.rest.RESTClient(token)

    proc on(event, handler):
        self.handlers[event] = handler

    proc send_message(channel_id, content):
        return self.http.send_message(channel_id, content)

    proc run():
        # This would handle the actual socket connection
        # For now, we simulate the structure
        print("Connecting to Discord Gateway...")
        # (WebSocket connection logic here)

    proc handle_message(msg):
        let payload = json.decode(msg)
        let op = payload["op"]
        
        if op == discord.types.OP_HELLO:
            self.heartbeat_interval = payload["d"]["heartbeat_interval"]
            print("Received HELLO, interval: " + str(self.heartbeat_interval))
            # Start heartbeats
            
        if op == discord.types.OP_DISPATCH:
            let event_name = payload["t"]
            if self.handlers[event_name]:
                self.handlers[event_name](payload["d"])
