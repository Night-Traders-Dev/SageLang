import std.testing as testing
import json
from discord import gateway
from discord import types

proc test_gateway_payloads():
    let identify = gateway.identify_payload("fake_token", 32767)
    let root = json.cJSON_Parse(identify)
    let payload = json.cJSON_ToSage(root)
    
    testing.assert_equal(payload["op"], types.OP_IDENTIFY, "Opcode should be Identify")
    testing.assert_equal(payload["d"]["token"], "fake_token", "Token should match")
    print("Gateway payload tests passed!")

proc run_all():
    test_gateway_payloads()

run_all()
