# lib/json.sage - cJSON port for SageLang
# 1:1 API port of Dave Gamble's cJSON (https://github.com/DaveGamble/cJSON)
#
# Usage:
#   from json import cJSON, cJSON_Parse, cJSON_Print, cJSON_Delete
#   let root = cJSON_Parse(json_string)
#   let name = cJSON_GetObjectItem(root, "name")
#   print cJSON_GetStringValue(name)
#   cJSON_Delete(root)

# ============================================================================
# Type constants (matching cJSON exactly) — evaluated at compile time
# ============================================================================

comptime:
    let cJSON_Invalid = 0
    let cJSON_False   = 1
    let cJSON_True    = 2
    let cJSON_NULL    = 4
    let cJSON_Number  = 8
    let cJSON_String  = 16
    let cJSON_Array   = 32
    let cJSON_Object  = 64
    let cJSON_Raw     = 128
    let CJSON_NESTING_LIMIT = 1000

# Escape handling — hot path, inlined for parser performance.
@inline
proc _handle_escape(esc):
    if esc == chr(34):
        return chr(34)
    if esc == chr(92):
        return chr(92)
    if esc == "/":
        return "/"
    if esc == "n":
        return chr(10)
    if esc == "r":
        return chr(13)
    if esc == "t":
        return chr(9)
    if esc == "b":
        return chr(8)
    if esc == "f":
        return chr(12)
    return esc

# ============================================================================
# cJSON node class (mirrors the C struct)
# ============================================================================

class cJSON:
    proc init():
        self.next = nil
        self.prev = nil
        self.child = nil
        self.type = cJSON_Invalid
        self.valuestring = nil
        self.valueint = 0
        self.valuedouble = 0
        self.string = nil

# ============================================================================
# Internal: Parser
# ============================================================================

let g_error_ptr = ""

class _Parser:
    proc init(source):
        self.src = source
        self.pos = 0
        self.slen = len(source)
        self.depth = 0

    proc peek():
        if self.pos >= self.slen:
            return ""
        return self.src[self.pos]

    proc advance():
        let c = self.src[self.pos]
        self.pos = self.pos + 1
        return c

    proc skip_ws():
        while self.pos < self.slen:
            let c = self.src[self.pos]
            if c == " " or c == chr(10) or c == chr(13) or c == chr(9):
                self.pos = self.pos + 1
            else:
                return

    proc parse_value():
        self.depth = self.depth + 1
        if self.depth > CJSON_NESTING_LIMIT:
            return nil
        self.skip_ws()
        if self.pos >= self.slen:
            self.depth = self.depth - 1
            return nil
        let c = self.src[self.pos]
        let result = nil
        if c == chr(34):
            result = self.parse_string_node()
        elif c == "{":
            result = self.parse_object()
        elif c == "[":
            result = self.parse_array()
        elif c == "t":
            result = self.parse_true()
        elif c == "f":
            result = self.parse_false()
        elif c == "n":
            result = self.parse_null()
        elif c == "-" or (c >= "0" and c <= "9"):
            result = self.parse_number()
        self.depth = self.depth - 1
        return result

    proc parse_string_raw():
        if self.pos >= self.slen or self.src[self.pos] != chr(34):
            return nil
        self.pos = self.pos + 1
        let result = ""
        while self.pos < self.slen:
            let c = self.src[self.pos]
            self.pos = self.pos + 1
            if c == chr(34):
                return result
            if c == chr(92):
                if self.pos >= self.slen:
                    return nil
                let esc = self.src[self.pos]
                self.pos = self.pos + 1
                if esc == "u":
                    let code = 0
                    let hi = 0
                    while hi < 4 and self.pos < self.slen:
                        let hc = self.src[self.pos]
                        self.pos = self.pos + 1
                        code = code * 16
                        if hc >= "0" and hc <= "9":
                            code = code + (ord(hc) - ord("0"))
                        elif hc >= "a" and hc <= "f":
                            code = code + 10 + (ord(hc) - ord("a"))
                        elif hc >= "A" and hc <= "F":
                            code = code + 10 + (ord(hc) - ord("A"))
                        hi = hi + 1
                    if code < 128:
                        result = result + chr(code)
                    else:
                        result = result + "?"
                else:
                    result = result + _handle_escape(esc)
            else:
                result = result + c
        return nil

    proc parse_string_node():
        let s = self.parse_string_raw()
        if s == nil:
            return nil
        let node = cJSON()
        node.type = cJSON_String
        node.valuestring = s
        return node

    proc parse_number():
        let start = self.pos
        if self.pos < self.slen and self.src[self.pos] == "-":
            self.pos = self.pos + 1
        while self.pos < self.slen and self.src[self.pos] >= "0" and self.src[self.pos] <= "9":
            self.pos = self.pos + 1
        if self.pos < self.slen and self.src[self.pos] == ".":
            self.pos = self.pos + 1
            while self.pos < self.slen and self.src[self.pos] >= "0" and self.src[self.pos] <= "9":
                self.pos = self.pos + 1
        if self.pos < self.slen and (self.src[self.pos] == "e" or self.src[self.pos] == "E"):
            self.pos = self.pos + 1
            if self.pos < self.slen and (self.src[self.pos] == "+" or self.src[self.pos] == "-"):
                self.pos = self.pos + 1
            while self.pos < self.slen and self.src[self.pos] >= "0" and self.src[self.pos] <= "9":
                self.pos = self.pos + 1
        let num_str = ""
        let i = start
        while i < self.pos:
            num_str = num_str + self.src[i]
            i = i + 1
        let val = tonumber(num_str)
        let node = cJSON()
        node.type = cJSON_Number
        node.valuedouble = val
        node.valueint = val
        return node

    proc parse_true():
        if self.pos + 4 <= self.slen:
            if self.src[self.pos] == "t" and self.src[self.pos+1] == "r" and self.src[self.pos+2] == "u" and self.src[self.pos+3] == "e":
                self.pos = self.pos + 4
                let node = cJSON()
                node.type = cJSON_True
                return node
        return nil

    proc parse_false():
        if self.pos + 5 <= self.slen:
            if self.src[self.pos] == "f" and self.src[self.pos+1] == "a" and self.src[self.pos+2] == "l" and self.src[self.pos+3] == "s" and self.src[self.pos+4] == "e":
                self.pos = self.pos + 5
                let node = cJSON()
                node.type = cJSON_False
                return node
        return nil

    proc parse_null():
        if self.pos + 4 <= self.slen:
            if self.src[self.pos] == "n" and self.src[self.pos+1] == "u" and self.src[self.pos+2] == "l" and self.src[self.pos+3] == "l":
                self.pos = self.pos + 4
                let node = cJSON()
                node.type = cJSON_NULL
                return node
        return nil

    proc parse_array():
        self.pos = self.pos + 1
        let node = cJSON()
        node.type = cJSON_Array
        self.skip_ws()
        if self.pos < self.slen and self.src[self.pos] == "]":
            self.pos = self.pos + 1
            return node
        let first = self.parse_value()
        if first == nil:
            return nil
        node.child = first
        let current = first
        while true:
            self.skip_ws()
            if self.pos >= self.slen:
                return nil
            if self.src[self.pos] == "]":
                self.pos = self.pos + 1
                return node
            if self.src[self.pos] != ",":
                return nil
            self.pos = self.pos + 1
            let next_item = self.parse_value()
            if next_item == nil:
                return nil
            current.next = next_item
            next_item.prev = current
            current = next_item

    proc parse_object():
        self.pos = self.pos + 1
        let node = cJSON()
        node.type = cJSON_Object
        self.skip_ws()
        if self.pos < self.slen and self.src[self.pos] == "}":
            self.pos = self.pos + 1
            return node
        let first = self.parse_kv()
        if first == nil:
            return nil
        node.child = first
        let current = first
        while true:
            self.skip_ws()
            if self.pos >= self.slen:
                return nil
            if self.src[self.pos] == "}":
                self.pos = self.pos + 1
                return node
            if self.src[self.pos] != ",":
                return nil
            self.pos = self.pos + 1
            let next_kv = self.parse_kv()
            if next_kv == nil:
                return nil
            current.next = next_kv
            next_kv.prev = current
            current = next_kv

    proc parse_kv():
        self.skip_ws()
        let key = self.parse_string_raw()
        if key == nil:
            return nil
        self.skip_ws()
        if self.pos >= self.slen or self.src[self.pos] != ":":
            return nil
        self.pos = self.pos + 1
        let val = self.parse_value()
        if val == nil:
            return nil
        val.string = key
        return val

# ============================================================================
# Internal: Printer
# ============================================================================

proc _escape_str(s):
    let result = ""
    let i = 0
    while i < len(s):
        let c = s[i]
        if c == chr(34):
            result = result + chr(92) + chr(34)
        elif c == chr(92):
            result = result + chr(92) + chr(92)
        elif c == chr(10):
            result = result + chr(92) + "n"
        elif c == chr(13):
            result = result + chr(92) + "r"
        elif c == chr(9):
            result = result + chr(92) + "t"
        elif c == chr(8):
            result = result + chr(92) + "b"
        elif c == chr(12):
            result = result + chr(92) + "f"
        else:
            result = result + c
        i = i + 1
    return result

proc _print_number(item):
    let s = str(item.valuedouble)
    if endswith(s, ".0"):
        let trimmed = ""
        let i = 0
        while i < len(s) - 2:
            trimmed = trimmed + s[i]
            i = i + 1
        return trimmed
    return s

proc _make_pad(indent, depth):
    let pad = ""
    let i = 0
    while i < indent * depth:
        pad = pad + " "
        i = i + 1
    return pad

proc _print_node(item, fmt, depth, indent):
    if item == nil:
        return "null"
    let t = item.type
    if t == cJSON_NULL:
        return "null"
    if t == cJSON_False:
        return "false"
    if t == cJSON_True:
        return "true"
    if t == cJSON_Number:
        return _print_number(item)
    if t == cJSON_String:
        return chr(34) + _escape_str(item.valuestring) + chr(34)
    if t == cJSON_Raw:
        if item.valuestring != nil:
            return item.valuestring
        return ""
    if t == cJSON_Array:
        let child = item.child
        if child == nil:
            return "[]"
        if fmt:
            let nl = chr(10)
            let pad = _make_pad(indent, depth + 1)
            let close_pad = _make_pad(indent, depth)
            let out = "[" + nl
            let first = true
            while child != nil:
                if not first:
                    out = out + "," + nl
                out = out + pad + _print_node(child, fmt, depth + 1, indent)
                first = false
                child = child.next
            return out + nl + close_pad + "]"
        else:
            let out = "["
            let first = true
            while child != nil:
                if not first:
                    out = out + ","
                out = out + _print_node(child, fmt, depth + 1, indent)
                first = false
                child = child.next
            return out + "]"
    if t == cJSON_Object:
        let child = item.child
        if child == nil:
            return "{}"
        if fmt:
            let nl = chr(10)
            let pad = _make_pad(indent, depth + 1)
            let close_pad = _make_pad(indent, depth)
            let out = "{" + nl
            let first = true
            while child != nil:
                if not first:
                    out = out + "," + nl
                out = out + pad + chr(34) + _escape_str(child.string) + chr(34) + ": " + _print_node(child, fmt, depth + 1, indent)
                first = false
                child = child.next
            return out + nl + close_pad + "}"
        else:
            let out = "{"
            let first = true
            while child != nil:
                if not first:
                    out = out + ","
                out = out + chr(34) + _escape_str(child.string) + chr(34) + ":" + _print_node(child, fmt, depth + 1, indent)
                first = false
                child = child.next
            return out + "}"
    return ""

# ============================================================================
# Parsing API
# ============================================================================

# cJSON_Parse(value) -> cJSON node or nil
proc cJSON_Parse(value):
    let p = _Parser(value)
    let result = p.parse_value()
    return result

# cJSON_ParseWithLength(value, buffer_length) -> cJSON node or nil
proc cJSON_ParseWithLength(value, buffer_length):
    if buffer_length < len(value):
        let sub = ""
        let i = 0
        while i < buffer_length:
            sub = sub + value[i]
            i = i + 1
        return cJSON_Parse(sub)
    return cJSON_Parse(value)

# cJSON_GetErrorPtr() -> string
@inline
proc cJSON_GetErrorPtr():
    return g_error_ptr

# ============================================================================
# Printing API
# ============================================================================

# cJSON_Print(item) -> formatted JSON string
proc cJSON_Print(item):
    return _print_node(item, true, 0, 4)

# cJSON_PrintUnformatted(item) -> compact JSON string
proc cJSON_PrintUnformatted(item):
    return _print_node(item, false, 0, 0)

# cJSON_PrintBuffered(item, prebuffer, fmt) -> JSON string
proc cJSON_PrintBuffered(item, prebuffer, fmt):
    if fmt:
        return cJSON_Print(item)
    return cJSON_PrintUnformatted(item)

# ============================================================================
# Creation API
# ============================================================================

# cJSON_CreateNull() -> cJSON node
proc cJSON_CreateNull():
    let node = cJSON()
    node.type = cJSON_NULL
    return node

# cJSON_CreateTrue() -> cJSON node
proc cJSON_CreateTrue():
    let node = cJSON()
    node.type = cJSON_True
    return node

# cJSON_CreateFalse() -> cJSON node
proc cJSON_CreateFalse():
    let node = cJSON()
    node.type = cJSON_False
    return node

# cJSON_CreateBool(boolean) -> cJSON node
proc cJSON_CreateBool(boolean):
    let node = cJSON()
    if boolean:
        node.type = cJSON_True
    else:
        node.type = cJSON_False
    return node

# cJSON_CreateNumber(num) -> cJSON node
proc cJSON_CreateNumber(num):
    let node = cJSON()
    node.type = cJSON_Number
    node.valuedouble = num
    node.valueint = num
    return node

# cJSON_CreateString(string) -> cJSON node
proc cJSON_CreateString(s):
    let node = cJSON()
    node.type = cJSON_String
    node.valuestring = s
    return node

# cJSON_CreateRaw(raw) -> cJSON node
proc cJSON_CreateRaw(raw):
    let node = cJSON()
    node.type = cJSON_Raw
    node.valuestring = raw
    return node

# cJSON_CreateArray() -> cJSON node
proc cJSON_CreateArray():
    let node = cJSON()
    node.type = cJSON_Array
    return node

# cJSON_CreateObject() -> cJSON node
proc cJSON_CreateObject():
    let node = cJSON()
    node.type = cJSON_Object
    return node

# cJSON_CreateIntArray(numbers) -> cJSON array node
proc cJSON_CreateIntArray(numbers):
    let arr = cJSON_CreateArray()
    let i = 0
    while i < len(numbers):
        cJSON_AddItemToArray(arr, cJSON_CreateNumber(numbers[i]))
        i = i + 1
    return arr

# cJSON_CreateDoubleArray(numbers) -> cJSON array node
proc cJSON_CreateDoubleArray(numbers):
    return cJSON_CreateIntArray(numbers)

# cJSON_CreateFloatArray(numbers) -> cJSON array node
proc cJSON_CreateFloatArray(numbers):
    return cJSON_CreateIntArray(numbers)

# cJSON_CreateStringArray(strings) -> cJSON array node
proc cJSON_CreateStringArray(strings):
    let arr = cJSON_CreateArray()
    let i = 0
    while i < len(strings):
        cJSON_AddItemToArray(arr, cJSON_CreateString(strings[i]))
        i = i + 1
    return arr

# ============================================================================
# Query API
# ============================================================================

# cJSON_GetArraySize(array) -> int
proc cJSON_GetArraySize(array):
    if array == nil:
        return 0
    let count = 0
    let child = array.child
    while child != nil:
        count = count + 1
        child = child.next
    return count

# cJSON_GetArrayItem(array, index) -> cJSON node or nil
proc cJSON_GetArrayItem(array, index):
    if array == nil:
        return nil
    let child = array.child
    let i = 0
    while child != nil and i < index:
        child = child.next
        i = i + 1
    return child

# cJSON_GetObjectItem(object, string) -> cJSON node or nil
proc cJSON_GetObjectItem(object, name):
    if object == nil:
        return nil
    let child = object.child
    while child != nil:
        if child.string != nil:
            if lower(child.string) == lower(name):
                return child
        child = child.next
    return nil

# cJSON_GetObjectItemCaseSensitive(object, string) -> cJSON node or nil
proc cJSON_GetObjectItemCaseSensitive(object, name):
    if object == nil:
        return nil
    let child = object.child
    while child != nil:
        if child.string != nil and child.string == name:
            return child
        child = child.next
    return nil

# cJSON_HasObjectItem(object, string) -> bool
@inline
proc cJSON_HasObjectItem(object, name):
    return cJSON_GetObjectItem(object, name) != nil

# cJSON_GetStringValue(item) -> string or nil
@inline
proc cJSON_GetStringValue(item):
    if item == nil:
        return nil
    if item.type != cJSON_String:
        return nil
    return item.valuestring

# cJSON_GetNumberValue(item) -> number
@inline
proc cJSON_GetNumberValue(item):
    if item == nil:
        return 0
    if item.type != cJSON_Number:
        return 0
    return item.valuedouble

# ============================================================================
# Type Checking API
# ============================================================================

@inline
proc cJSON_IsInvalid(item):
    if item == nil:
        return false
    return item.type == cJSON_Invalid

@inline
proc cJSON_IsFalse(item):
    if item == nil:
        return false
    return item.type == cJSON_False

@inline
proc cJSON_IsTrue(item):
    if item == nil:
        return false
    return item.type == cJSON_True

@inline
proc cJSON_IsBool(item):
    if item == nil:
        return false
    return item.type == cJSON_True or item.type == cJSON_False

@inline
proc cJSON_IsNull(item):
    if item == nil:
        return false
    return item.type == cJSON_NULL

@inline
proc cJSON_IsNumber(item):
    if item == nil:
        return false
    return item.type == cJSON_Number

@inline
proc cJSON_IsString(item):
    if item == nil:
        return false
    return item.type == cJSON_String

@inline
proc cJSON_IsArray(item):
    if item == nil:
        return false
    return item.type == cJSON_Array

@inline
proc cJSON_IsObject(item):
    if item == nil:
        return false
    return item.type == cJSON_Object

@inline
proc cJSON_IsRaw(item):
    if item == nil:
        return false
    return item.type == cJSON_Raw

# ============================================================================
# Array Modification API
# ============================================================================

# cJSON_AddItemToArray(array, item) -> bool
proc cJSON_AddItemToArray(array, item):
    if array == nil or item == nil:
        return false
    if array.child == nil:
        array.child = item
        item.prev = nil
        item.next = nil
        return true
    let last = array.child
    while last.next != nil:
        last = last.next
    last.next = item
    item.prev = last
    item.next = nil
    return true

# cJSON_InsertItemInArray(array, which, newitem) -> bool
proc cJSON_InsertItemInArray(array, which, newitem):
    if array == nil or newitem == nil:
        return false
    if which == 0:
        newitem.next = array.child
        if array.child != nil:
            array.child.prev = newitem
        array.child = newitem
        newitem.prev = nil
        return true
    let child = array.child
    let i = 0
    while child != nil and i < which - 1:
        child = child.next
        i = i + 1
    if child == nil:
        return cJSON_AddItemToArray(array, newitem)
    newitem.next = child.next
    if child.next != nil:
        child.next.prev = newitem
    child.next = newitem
    newitem.prev = child
    return true

# cJSON_DetachItemFromArray(array, which) -> detached cJSON node or nil
proc cJSON_DetachItemFromArray(array, which):
    if array == nil:
        return nil
    let child = array.child
    let i = 0
    while child != nil and i < which:
        child = child.next
        i = i + 1
    if child == nil:
        return nil
    return cJSON_DetachItemViaPointer(array, child)

# cJSON_DeleteItemFromArray(array, which) -> nil
proc cJSON_DeleteItemFromArray(array, which):
    cJSON_DetachItemFromArray(array, which)

# cJSON_ReplaceItemInArray(array, which, newitem) -> bool
proc cJSON_ReplaceItemInArray(array, which, newitem):
    if array == nil or newitem == nil:
        return false
    let child = array.child
    let i = 0
    while child != nil and i < which:
        child = child.next
        i = i + 1
    if child == nil:
        return false
    return cJSON_ReplaceItemViaPointer(array, child, newitem)

# ============================================================================
# Object Modification API
# ============================================================================

# cJSON_AddItemToObject(object, string, item) -> bool
proc cJSON_AddItemToObject(object, name, item):
    if object == nil or item == nil or name == nil:
        return false
    item.string = name
    return cJSON_AddItemToArray(object, item)

# cJSON_AddItemToObjectCS(object, string, item) -> bool (same as above in Sage)
proc cJSON_AddItemToObjectCS(object, name, item):
    return cJSON_AddItemToObject(object, name, item)

# cJSON_DetachItemFromObject(object, string) -> detached node or nil
proc cJSON_DetachItemFromObject(object, name):
    if object == nil:
        return nil
    let item = cJSON_GetObjectItem(object, name)
    if item == nil:
        return nil
    return cJSON_DetachItemViaPointer(object, item)

# cJSON_DetachItemFromObjectCaseSensitive(object, string) -> detached node or nil
proc cJSON_DetachItemFromObjectCaseSensitive(object, name):
    if object == nil:
        return nil
    let item = cJSON_GetObjectItemCaseSensitive(object, name)
    if item == nil:
        return nil
    return cJSON_DetachItemViaPointer(object, item)

# cJSON_DeleteItemFromObject(object, string)
proc cJSON_DeleteItemFromObject(object, name):
    cJSON_DetachItemFromObject(object, name)

# cJSON_DeleteItemFromObjectCaseSensitive(object, string)
proc cJSON_DeleteItemFromObjectCaseSensitive(object, name):
    cJSON_DetachItemFromObjectCaseSensitive(object, name)

# cJSON_ReplaceItemInObject(object, string, newitem) -> bool
proc cJSON_ReplaceItemInObject(object, name, newitem):
    if object == nil or newitem == nil:
        return false
    newitem.string = name
    let item = cJSON_GetObjectItem(object, name)
    if item == nil:
        return cJSON_AddItemToObject(object, name, newitem)
    return cJSON_ReplaceItemViaPointer(object, item, newitem)

# cJSON_ReplaceItemInObjectCaseSensitive(object, string, newitem) -> bool
proc cJSON_ReplaceItemInObjectCaseSensitive(object, name, newitem):
    if object == nil or newitem == nil:
        return false
    newitem.string = name
    let item = cJSON_GetObjectItemCaseSensitive(object, name)
    if item == nil:
        return cJSON_AddItemToObject(object, name, newitem)
    return cJSON_ReplaceItemViaPointer(object, item, newitem)

# ============================================================================
# Generic Modification API
# ============================================================================

# cJSON_DetachItemViaPointer(parent, item) -> detached item
# Note: Uses item.prev == nil instead of parent.child == item because
# Sage instance == always returns false (no reference equality).
proc cJSON_DetachItemViaPointer(parent, item):
    if parent == nil or item == nil:
        return nil
    if item.prev == nil:
        parent.child = item.next
    if item.prev != nil:
        item.prev.next = item.next
    if item.next != nil:
        item.next.prev = item.prev
    item.prev = nil
    item.next = nil
    return item

# cJSON_ReplaceItemViaPointer(parent, item, replacement) -> bool
# Note: Uses item.prev == nil instead of parent.child == item because
# Sage instance == always returns false (no reference equality).
proc cJSON_ReplaceItemViaPointer(parent, item, replacement):
    if parent == nil or item == nil or replacement == nil:
        return false
    replacement.next = item.next
    replacement.prev = item.prev
    if replacement.next != nil:
        replacement.next.prev = replacement
    if item.prev == nil:
        parent.child = replacement
    if replacement.prev != nil:
        replacement.prev.next = replacement
    replacement.string = item.string
    return true

# ============================================================================
# Helper: Add-to-Object convenience functions
# ============================================================================

proc cJSON_AddNullToObject(object, name):
    return cJSON_AddItemToObject(object, name, cJSON_CreateNull())

proc cJSON_AddTrueToObject(object, name):
    return cJSON_AddItemToObject(object, name, cJSON_CreateTrue())

proc cJSON_AddFalseToObject(object, name):
    return cJSON_AddItemToObject(object, name, cJSON_CreateFalse())

proc cJSON_AddBoolToObject(object, name, boolean):
    return cJSON_AddItemToObject(object, name, cJSON_CreateBool(boolean))

proc cJSON_AddNumberToObject(object, name, number):
    return cJSON_AddItemToObject(object, name, cJSON_CreateNumber(number))

proc cJSON_AddStringToObject(object, name, s):
    return cJSON_AddItemToObject(object, name, cJSON_CreateString(s))

proc cJSON_AddRawToObject(object, name, raw):
    return cJSON_AddItemToObject(object, name, cJSON_CreateRaw(raw))

proc cJSON_AddArrayToObject(object, name):
    let arr = cJSON_CreateArray()
    cJSON_AddItemToObject(object, name, arr)
    return arr

proc cJSON_AddObjectToObject(object, name):
    let obj = cJSON_CreateObject()
    cJSON_AddItemToObject(object, name, obj)
    return obj

# ============================================================================
# Utility API
# ============================================================================

# cJSON_Duplicate(item, recurse) -> new cJSON tree
proc cJSON_Duplicate(item, recurse):
    if item == nil:
        return nil
    let node = cJSON()
    node.type = item.type
    node.valuestring = item.valuestring
    node.valueint = item.valueint
    node.valuedouble = item.valuedouble
    node.string = item.string
    if recurse and item.child != nil:
        let src_child = item.child
        let prev_copy = nil
        let first_copy = nil
        while src_child != nil:
            let child_copy = cJSON_Duplicate(src_child, true)
            if first_copy == nil:
                first_copy = child_copy
            if prev_copy != nil:
                prev_copy.next = child_copy
                child_copy.prev = prev_copy
            prev_copy = child_copy
            src_child = src_child.next
        node.child = first_copy
    return node

# cJSON_Compare(a, b, case_sensitive) -> bool
proc cJSON_Compare(a, b, case_sensitive):
    if a == nil and b == nil:
        return true
    if a == nil or b == nil:
        return false
    if a.type != b.type:
        return false
    let t = a.type
    if t == cJSON_False or t == cJSON_True or t == cJSON_NULL:
        return true
    if t == cJSON_Number:
        return a.valuedouble == b.valuedouble
    if t == cJSON_String or t == cJSON_Raw:
        if a.valuestring == nil and b.valuestring == nil:
            return true
        if a.valuestring == nil or b.valuestring == nil:
            return false
        return a.valuestring == b.valuestring
    if t == cJSON_Array:
        let ac = a.child
        let bc = b.child
        while ac != nil and bc != nil:
            if not cJSON_Compare(ac, bc, case_sensitive):
                return false
            ac = ac.next
            bc = bc.next
        return ac == nil and bc == nil
    if t == cJSON_Object:
        let ac = a.child
        while ac != nil:
            let key = ac.string
            let bval = nil
            if case_sensitive:
                bval = cJSON_GetObjectItemCaseSensitive(b, key)
            else:
                bval = cJSON_GetObjectItem(b, key)
            if bval == nil:
                return false
            if not cJSON_Compare(ac, bval, case_sensitive):
                return false
            ac = ac.next
        let bc = b.child
        while bc != nil:
            let key = bc.string
            let aval = nil
            if case_sensitive:
                aval = cJSON_GetObjectItemCaseSensitive(a, key)
            else:
                aval = cJSON_GetObjectItem(a, key)
            if aval == nil:
                return false
            bc = bc.next
        return true
    return false

# cJSON_Minify(json) -> minified string
proc cJSON_Minify(json):
    let node = cJSON_Parse(json)
    if node == nil:
        return json
    return cJSON_PrintUnformatted(node)

# cJSON_Delete(item) -> nil (no-op in GC language, included for API compat)
proc cJSON_Delete(item):
    return nil

# cJSON_SetValuestring(object, valuestring) -> string
proc cJSON_SetValuestring(object, valuestring):
    if object == nil:
        return nil
    object.valuestring = valuestring
    return valuestring

# cJSON_SetNumberHelper(object, number) -> number
proc cJSON_SetNumberHelper(object, number):
    if object == nil:
        return 0
    object.valuedouble = number
    object.valueint = number
    return number

# cJSON_Version() -> string
proc cJSON_Version():
    return "1.7.18-sage"

# ============================================================================
# Convenience: Native Sage value conversion
# ============================================================================

# Convert cJSON tree to native Sage values (dict/array/string/number/bool/nil)
proc cJSON_ToSage(item):
    if item == nil:
        return nil
    let t = item.type
    if t == cJSON_NULL:
        return nil
    if t == cJSON_False:
        return false
    if t == cJSON_True:
        return true
    if t == cJSON_Number:
        return item.valuedouble
    if t == cJSON_String:
        return item.valuestring
    if t == cJSON_Array:
        let arr = []
        let child = item.child
        while child != nil:
            push(arr, cJSON_ToSage(child))
            child = child.next
        return arr
    if t == cJSON_Object:
        let obj = {}
        let child = item.child
        while child != nil:
            if child.string != nil:
                obj[child.string] = cJSON_ToSage(child)
            child = child.next
        return obj
    return nil

# Convert native Sage value to cJSON tree
proc cJSON_FromSage(val):
    if val == nil:
        return cJSON_CreateNull()
    let t = type(val)
    if t == "bool":
        return cJSON_CreateBool(val)
    if t == "number":
        return cJSON_CreateNumber(val)
    if t == "string":
        return cJSON_CreateString(val)
    if t == "array":
        let arr = cJSON_CreateArray()
        let i = 0
        while i < len(val):
            cJSON_AddItemToArray(arr, cJSON_FromSage(val[i]))
            i = i + 1
        return arr
    if t == "dict":
        let obj = cJSON_CreateObject()
        let keys = dict_keys(val)
        let i = 0
        while i < len(keys):
            cJSON_AddItemToObject(obj, keys[i], cJSON_FromSage(val[keys[i]]))
            i = i + 1
        return obj
    return cJSON_CreateNull()
