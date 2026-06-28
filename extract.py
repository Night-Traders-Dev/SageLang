import json

found = False
with open("/home/kraken/.gemini/antigravity-cli/brain/318d9226-0371-4df4-a60e-6bfe1fdabfda/.system_generated/logs/transcript_full.jsonl") as f:
    for line in f:
        if "class SageToLilyTranspiler:" in line:
            data = json.loads(line)
            if "tool_calls" in data:
                for call in data["tool_calls"]:
                    if "sage_to_lily.sage" in str(call):
                        args = call.get("arguments", {})
                        if "CodeContent" in args:
                            with open("sage_to_lily.sage.restored", "w") as out:
                                out.write(args["CodeContent"])
                            print("Restored!")
                            found = True
                            break
            if found: break
if not found:
    print("Not found in transcript")
