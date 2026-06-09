# lib/blockchain/db.sage

import io
import json
import sys

class LedgerDB:
    proc init(base_dir):
        self.base_dir = base_dir
        self.height_dir = base_dir + "/height"
        self.hash_dir = base_dir + "/hash"
        self.account_dir = base_dir + "/accounts"
        self.contract_dir = base_dir + "/contracts"
        self.tx_history_dir = base_dir + "/tx_history"
        self.tx_dir = base_dir + "/tx"
        self.ensure_dirs()

    proc ensure_dirs():
        if not io.exists(self.base_dir):
            io.mkdir(self.base_dir)
        if not io.exists(self.height_dir):
            io.mkdir(self.height_dir)
        if not io.exists(self.hash_dir):
            io.mkdir(self.hash_dir)
        if not io.exists(self.account_dir):
            io.mkdir(self.account_dir)
        if not io.exists(self.contract_dir):
            io.mkdir(self.contract_dir)
        if not io.exists(self.tx_history_dir):
            io.mkdir(self.tx_history_dir)
        if not io.exists(self.tx_dir):
            io.mkdir(self.tx_dir)

    proc save_block(block):
        let height = block.index
        let hash = block.hash
        
        # Serialize block to JSON
        let block_dict = block.to_dict()
        let cjson_obj = json.cJSON_FromSage(block_dict)
        let json_str = json.cJSON_PrintUnformatted(cjson_obj)
        json.cJSON_Delete(cjson_obj)
        
        # Save by height
        io.writefile(self.height_dir + "/" + str(height) + ".json", json_str)
        
        # Save hash index (content is height)
        io.writefile(self.hash_dir + "/" + hash, str(height))

    proc get_block_by_height(height):
        let path = self.height_dir + "/" + str(height) + ".json"
        if not io.exists(path):
            return nil
            
        let json_str = io.readfile(path)
        let cjson_obj = json.cJSON_Parse(json_str)
        let block_dict = json.cJSON_ToSage(cjson_obj)
        json.cJSON_Delete(cjson_obj)
        return block_dict

    proc get_block_by_hash(hash):
        let path = self.hash_dir + "/" + hash
        if not io.exists(path):
            return nil
        let height_str = io.readfile(path)
        return self.get_block_by_height(tonumber(height_str))

    proc save_account_balance(address, balance):
        io.writefile(self.account_dir + "/" + address, str(balance))

    proc get_account_balance(address):
        let path = self.account_dir + "/" + address
        if not io.exists(path):
            return 0.0
        return tonumber(io.readfile(path))

    proc save_contract_state(address, state):
        let cjson_obj = json.cJSON_FromSage(state)
        let json_str = json.cJSON_PrintUnformatted(cjson_obj)
        json.cJSON_Delete(cjson_obj)
        
        let dir = self.contract_dir + "/" + address
        if not io.exists(dir):
            io.mkdir(dir)
        io.writefile(dir + "/state.json", json_str)

    proc get_contract_state(address):
        let path = self.contract_dir + "/" + address + "/state.json"
        if not io.exists(path):
            return {}
        let json_str = io.readfile(path)
        let cjson_obj = json.cJSON_Parse(json_str)
        let state = json.cJSON_ToSage(cjson_obj)
        json.cJSON_Delete(cjson_obj)
        return state

    proc append_tx_to_history(address, tx_hash):
        let path = self.tx_history_dir + "/" + address
        io.appendfile(path, tx_hash + "\n")

    proc get_tx_history(address):
        let path = self.tx_history_dir + "/" + address
        if not io.exists(path):
            return []
        let hashes_str = io.readfile(path)
        return split(strip(hashes_str), "\n")

    proc save_transaction(tx_dict):
        let h = tx_dict["hash"]
        let cjson_obj = json.cJSON_FromSage(tx_dict)
        let json_str = json.cJSON_PrintUnformatted(cjson_obj)
        json.cJSON_Delete(cjson_obj)
        io.writefile(self.tx_dir + "/" + h + ".json", json_str)

    proc get_transaction(tx_hash):
        let path = self.tx_dir + "/" + tx_hash + ".json"
        if not io.exists(path):
            return nil
        let json_str = io.readfile(path)
        let cjson_obj = json.cJSON_Parse(json_str)
        let tx = json.cJSON_ToSage(cjson_obj)
        json.cJSON_Delete(cjson_obj)
        return tx
