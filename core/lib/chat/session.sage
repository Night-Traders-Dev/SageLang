gc_disable()
# Chat session management and multi-turn conversation tracking
# Handles conversation state, history export, and session persistence

import io

# ============================================================================
# Session
# ============================================================================

proc create_session(session_id, bot_name):
    let session = {}
    session["id"] = session_id
    session["bot"] = bot_name
    session["messages"] = []
    session["metadata"] = {}
    session["created"] = clock()
    session["last_active"] = clock()
    session["turn_count"] = 0
    session["active"] = true
    return session

proc add_turn(session, user_msg, bot_response):
    let turn = {}
    turn["user"] = user_msg
    turn["bot"] = bot_response
    turn["timestamp"] = clock()
    turn["turn_num"] = session["turn_count"]
    push(session["messages"], turn)
    session["turn_count"] = session["turn_count"] + 1
    session["last_active"] = clock()

proc get_history(session, max_turns):
    let msgs = session["messages"]
    let start = 0
    if len(msgs) > max_turns:
        start = len(msgs) - max_turns
    let result = []
    for i in range(len(msgs) - start):
        push(result, msgs[start + i])
    return result

proc close_session(session):
    session["active"] = false

# ============================================================================
# Session store (manages multiple sessions)
# ============================================================================

proc create_store():
    let store = {}
    store["sessions"] = {}
    store["total_sessions"] = 0
    return store

proc new_session(store, bot_name):
    let sid = "session_" + str(store["total_sessions"] + 1)
    let session = create_session(sid, bot_name)
    store["sessions"][sid] = session
    store["total_sessions"] = store["total_sessions"] + 1
    return session

proc get_session(store, session_id):
    if dict_has(store["sessions"], session_id):
        return store["sessions"][session_id]
    return nil

proc list_sessions(store):
    return dict_keys(store["sessions"])

proc active_sessions(store):
    let result = []
    let keys = dict_keys(store["sessions"])
    for i in range(len(keys)):
        if store["sessions"][keys[i]]["active"]:
            push(result, store["sessions"][keys[i]])
    return result

# ============================================================================
# Export
# ============================================================================

proc export_text(session):
    let nl = chr(10)
    let out = "=== Chat Session: " + session["id"] + " ===" + nl
    out = out + "Bot: " + session["bot"] + nl
    out = out + "Turns: " + str(session["turn_count"]) + nl + nl
    let msgs = session["messages"]
    for i in range(len(msgs)):
        out = out + "User: " + msgs[i]["user"] + nl
        out = out + "Bot: " + msgs[i]["bot"] + nl + nl
    return out

proc export_json_like(session):
    let nl = chr(10)
    let out = "{" + nl
    out = out + "  " + chr(34) + "session_id" + chr(34) + ": " + chr(34) + session["id"] + chr(34) + "," + nl
    out = out + "  " + chr(34) + "bot" + chr(34) + ": " + chr(34) + session["bot"] + chr(34) + "," + nl
    out = out + "  " + chr(34) + "turns" + chr(34) + ": " + str(session["turn_count"]) + "," + nl
    out = out + "  " + chr(34) + "messages" + chr(34) + ": [" + nl
    let msgs = session["messages"]
    for i in range(len(msgs)):
        out = out + "    {" + chr(34) + "user" + chr(34) + ": " + chr(34) + msgs[i]["user"] + chr(34) + ", "
        out = out + chr(34) + "bot" + chr(34) + ": " + chr(34) + msgs[i]["bot"] + chr(34) + "}"
        if i < len(msgs) - 1:
            out = out + ","
        out = out + nl
    out = out + "  ]" + nl + "}" + nl
    return out

proc save_session(session, path):
    let text = export_text(session)
    io.writefile(path, text)
    return path
