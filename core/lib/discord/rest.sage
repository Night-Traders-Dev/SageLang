import net.request
import json

class RESTClient:
    proc init(token):
        self.token = token
        self.base_url = "https://discord.com/api/v10"

    proc _request(method, path, data):
        let url = self.base_url + path
        let req = net.request.create(method, url)
        net.request.set_header(req, "Authorization", "Bot " + self.token)
        net.request.set_header(req, "Content-Type", "application/json")
        if data != nil:
            net.request.set_body(req, json.encode(data))
        
        let resp = net.request.send(req)
        return json.decode(resp["body"])

    proc get(path):
        return self._request("GET", path, nil)

    proc post(path, data):
        return self._request("POST", path, data)

    proc send_message(channel_id, content):
        let data = {"content": content}
        return self.post("/channels/" + str(channel_id) + "/messages", data)
