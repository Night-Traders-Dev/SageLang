gc_disable()

from json import cJSON, cJSON_Parse, cJSON_Print, cJSON_PrintUnformatted
from json import cJSON_CreateObject, cJSON_CreateArray, cJSON_CreateString
from json import cJSON_CreateNumber, cJSON_CreateNull, cJSON_CreateTrue, cJSON_CreateFalse
from json import cJSON_CreateBool
from json import cJSON_AddItemToObject, cJSON_AddItemToArray
from json import cJSON_AddStringToObject, cJSON_AddNumberToObject, cJSON_AddBoolToObject
from json import cJSON_AddNullToObject, cJSON_AddTrueToObject, cJSON_AddFalseToObject
from json import cJSON_AddArrayToObject, cJSON_AddObjectToObject
from json import cJSON_GetObjectItem, cJSON_GetObjectItemCaseSensitive
from json import cJSON_HasObjectItem, cJSON_GetArraySize, cJSON_GetArrayItem
from json import cJSON_GetStringValue, cJSON_GetNumberValue
from json import cJSON_IsObject, cJSON_IsArray, cJSON_IsString, cJSON_IsNumber
from json import cJSON_IsTrue, cJSON_IsFalse, cJSON_IsBool, cJSON_IsNull, cJSON_IsRaw
from json import cJSON_Delete, cJSON_Duplicate, cJSON_Compare, cJSON_Minify
from json import cJSON_DetachItemFromArray, cJSON_DeleteItemFromArray
from json import cJSON_InsertItemInArray, cJSON_ReplaceItemInArray
from json import cJSON_DetachItemFromObject, cJSON_DeleteItemFromObject
from json import cJSON_ReplaceItemInObject
from json import cJSON_SetValuestring, cJSON_SetNumberHelper, cJSON_Version
from json import cJSON_ToSage, cJSON_FromSage
from json import cJSON_ParseWithLength
from json import cJSON_CreateIntArray, cJSON_CreateStringArray
from json import cJSON_CreateRaw, cJSON_AddRawToObject

let passed = 0
let failed = 0

proc assert_eq(a, b, msg):
    if a == b:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (got " + str(a) + ", expected " + str(b) + ")"

proc assert_true(val, msg):
    if val:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

# ============================================================================
# Test 1: Parse simple object
# ============================================================================
print "--- Test 1: Parse simple object ---"
let json_str = "{" + chr(34) + "name" + chr(34) + ":" + chr(34) + "Alice" + chr(34) + "," + chr(34) + "age" + chr(34) + ":30}"
let root = cJSON_Parse(json_str)
assert_true(root != nil, "parse returns non-nil")
assert_true(cJSON_IsObject(root), "root is object")
let name_item = cJSON_GetObjectItem(root, "name")
assert_true(name_item != nil, "name item found")
assert_eq(cJSON_GetStringValue(name_item), "Alice", "name value")
let age_item = cJSON_GetObjectItem(root, "age")
assert_true(age_item != nil, "age item found")
assert_eq(cJSON_GetNumberValue(age_item), 30, "age value")

# ============================================================================
# Test 2: Parse array
# ============================================================================
print "--- Test 2: Parse array ---"
let arr_str = "[1,2,3," + chr(34) + "hello" + chr(34) + ",true,false,null]"
let arr = cJSON_Parse(arr_str)
assert_true(arr != nil, "parse array non-nil")
assert_true(cJSON_IsArray(arr), "root is array")
assert_eq(cJSON_GetArraySize(arr), 7, "array size is 7")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(arr, 0)), 1, "arr[0] == 1")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(arr, 1)), 2, "arr[1] == 2")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(arr, 2)), 3, "arr[2] == 3")
assert_eq(cJSON_GetStringValue(cJSON_GetArrayItem(arr, 3)), "hello", "arr[3] == hello")
assert_true(cJSON_IsTrue(cJSON_GetArrayItem(arr, 4)), "arr[4] is true")
assert_true(cJSON_IsFalse(cJSON_GetArrayItem(arr, 5)), "arr[5] is false")
assert_true(cJSON_IsNull(cJSON_GetArrayItem(arr, 6)), "arr[6] is null")

# ============================================================================
# Test 3: Create object with helpers
# ============================================================================
print "--- Test 3: Create object with helpers ---"
let obj = cJSON_CreateObject()
cJSON_AddStringToObject(obj, "city", "Portland")
cJSON_AddNumberToObject(obj, "pop", 650000)
cJSON_AddBoolToObject(obj, "cool", true)
cJSON_AddNullToObject(obj, "nothing")
assert_eq(cJSON_GetArraySize(obj), 4, "object has 4 items")
assert_eq(cJSON_GetStringValue(cJSON_GetObjectItem(obj, "city")), "Portland", "city value")
assert_eq(cJSON_GetNumberValue(cJSON_GetObjectItem(obj, "pop")), 650000, "pop value")
assert_true(cJSON_IsTrue(cJSON_GetObjectItem(obj, "cool")), "cool is true")
assert_true(cJSON_IsNull(cJSON_GetObjectItem(obj, "nothing")), "nothing is null")

# ============================================================================
# Test 4: Print formatted and unformatted
# ============================================================================
print "--- Test 4: Print formatted and unformatted ---"
let small = cJSON_CreateObject()
cJSON_AddStringToObject(small, "k", "v")
let compact = cJSON_PrintUnformatted(small)
assert_eq(compact, "{" + chr(34) + "k" + chr(34) + ":" + chr(34) + "v" + chr(34) + "}", "compact print")
let pretty = cJSON_Print(small)
assert_true(len(pretty) > len(compact), "formatted is longer than compact")

# ============================================================================
# Test 5: Nested objects
# ============================================================================
print "--- Test 5: Nested objects ---"
let nested_str = "{" + chr(34) + "a" + chr(34) + ":{" + chr(34) + "b" + chr(34) + ":{" + chr(34) + "c" + chr(34) + ":42}}}"
let nested = cJSON_Parse(nested_str)
assert_true(nested != nil, "parse nested")
let a = cJSON_GetObjectItem(nested, "a")
assert_true(cJSON_IsObject(a), "a is object")
let b = cJSON_GetObjectItem(a, "b")
assert_true(cJSON_IsObject(b), "b is object")
let c = cJSON_GetObjectItem(b, "c")
assert_eq(cJSON_GetNumberValue(c), 42, "nested c == 42")

# ============================================================================
# Test 6: Roundtrip (parse -> print -> parse)
# ============================================================================
print "--- Test 6: Roundtrip ---"
let rt_str = "{" + chr(34) + "x" + chr(34) + ":1," + chr(34) + "y" + chr(34) + ":[2,3]}"
let rt1 = cJSON_Parse(rt_str)
let rt_out = cJSON_PrintUnformatted(rt1)
let rt2 = cJSON_Parse(rt_out)
assert_true(cJSON_Compare(rt1, rt2, true), "roundtrip compare")

# ============================================================================
# Test 7: Type checks
# ============================================================================
print "--- Test 7: Type checks ---"
assert_true(cJSON_IsString(cJSON_CreateString("hi")), "isString")
assert_true(cJSON_IsNumber(cJSON_CreateNumber(42)), "isNumber")
assert_true(cJSON_IsTrue(cJSON_CreateTrue()), "isTrue")
assert_true(cJSON_IsFalse(cJSON_CreateFalse()), "isFalse")
assert_true(cJSON_IsBool(cJSON_CreateTrue()), "isBool true")
assert_true(cJSON_IsBool(cJSON_CreateFalse()), "isBool false")
assert_true(cJSON_IsNull(cJSON_CreateNull()), "isNull")
assert_true(cJSON_IsArray(cJSON_CreateArray()), "isArray")
assert_true(cJSON_IsObject(cJSON_CreateObject()), "isObject")
assert_true(cJSON_IsRaw(cJSON_CreateRaw("raw")), "isRaw")

# ============================================================================
# Test 8: HasObjectItem
# ============================================================================
print "--- Test 8: HasObjectItem ---"
let ho = cJSON_CreateObject()
cJSON_AddStringToObject(ho, "exists", "yes")
assert_true(cJSON_HasObjectItem(ho, "exists"), "has exists")
assert_true(not cJSON_HasObjectItem(ho, "nope"), "not has nope")

# ============================================================================
# Test 9: Array manipulation
# ============================================================================
print "--- Test 9: Array manipulation ---"
let ma = cJSON_CreateArray()
cJSON_AddItemToArray(ma, cJSON_CreateNumber(10))
cJSON_AddItemToArray(ma, cJSON_CreateNumber(20))
cJSON_AddItemToArray(ma, cJSON_CreateNumber(30))
assert_eq(cJSON_GetArraySize(ma), 3, "array size 3")

# Insert at beginning
cJSON_InsertItemInArray(ma, 0, cJSON_CreateNumber(5))
assert_eq(cJSON_GetArraySize(ma), 4, "array size after insert")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(ma, 0)), 5, "inserted at 0")

# Detach
let detached = cJSON_DetachItemFromArray(ma, 1)
assert_true(detached != nil, "detached non-nil")
assert_eq(cJSON_GetNumberValue(detached), 10, "detached value")
assert_eq(cJSON_GetArraySize(ma), 3, "array size after detach")

# Replace
cJSON_ReplaceItemInArray(ma, 0, cJSON_CreateNumber(99))
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(ma, 0)), 99, "replaced at 0")

# Delete
cJSON_DeleteItemFromArray(ma, 0)
assert_eq(cJSON_GetArraySize(ma), 2, "array size after delete")

# ============================================================================
# Test 10: Object manipulation
# ============================================================================
print "--- Test 10: Object manipulation ---"
let mo = cJSON_CreateObject()
cJSON_AddStringToObject(mo, "a", "1")
cJSON_AddStringToObject(mo, "b", "2")
cJSON_AddStringToObject(mo, "c", "3")
assert_eq(cJSON_GetArraySize(mo), 3, "obj size 3")

cJSON_DeleteItemFromObject(mo, "b")
assert_eq(cJSON_GetArraySize(mo), 2, "obj size after delete")
assert_true(not cJSON_HasObjectItem(mo, "b"), "b removed")

cJSON_ReplaceItemInObject(mo, "a", cJSON_CreateNumber(999))
assert_eq(cJSON_GetNumberValue(cJSON_GetObjectItem(mo, "a")), 999, "replaced a")

# ============================================================================
# Test 11: Duplicate
# ============================================================================
print "--- Test 11: Duplicate ---"
let orig = cJSON_CreateObject()
cJSON_AddStringToObject(orig, "key", "val")
let inner_arr = cJSON_AddArrayToObject(orig, "arr")
cJSON_AddItemToArray(inner_arr, cJSON_CreateNumber(1))
cJSON_AddItemToArray(inner_arr, cJSON_CreateNumber(2))

let dup = cJSON_Duplicate(orig, true)
assert_true(cJSON_Compare(orig, dup, true), "duplicate matches original")
# Modify duplicate, original should be unaffected
cJSON_AddStringToObject(dup, "extra", "field")
assert_true(not cJSON_HasObjectItem(orig, "extra"), "original unmodified after dup change")

# ============================================================================
# Test 12: Compare
# ============================================================================
print "--- Test 12: Compare ---"
let ca = cJSON_Parse("{" + chr(34) + "x" + chr(34) + ":1}")
let cb = cJSON_Parse("{" + chr(34) + "x" + chr(34) + ":1}")
let cc = cJSON_Parse("{" + chr(34) + "x" + chr(34) + ":2}")
assert_true(cJSON_Compare(ca, cb, true), "same objects compare equal")
assert_true(not cJSON_Compare(ca, cc, true), "different values not equal")

# ============================================================================
# Test 13: Case-insensitive vs case-sensitive lookup
# ============================================================================
print "--- Test 13: Case sensitivity ---"
let cs = cJSON_CreateObject()
cJSON_AddStringToObject(cs, "Name", "test")
let found_ci = cJSON_GetObjectItem(cs, "name")
assert_true(found_ci != nil, "case-insensitive finds Name as name")
let found_cs = cJSON_GetObjectItemCaseSensitive(cs, "name")
assert_true(found_cs == nil, "case-sensitive does not find name for Name")
let found_exact = cJSON_GetObjectItemCaseSensitive(cs, "Name")
assert_true(found_exact != nil, "case-sensitive finds exact Name")

# ============================================================================
# Test 14: SetValuestring and SetNumberHelper
# ============================================================================
print "--- Test 14: Set helpers ---"
let sv = cJSON_CreateString("old")
cJSON_SetValuestring(sv, "new")
assert_eq(cJSON_GetStringValue(sv), "new", "SetValuestring")

let sn = cJSON_CreateNumber(10)
cJSON_SetNumberHelper(sn, 42)
assert_eq(cJSON_GetNumberValue(sn), 42, "SetNumberHelper")

# ============================================================================
# Test 15: Minify
# ============================================================================
print "--- Test 15: Minify ---"
let spaced = "{  " + chr(34) + "a" + chr(34) + " :  1 , " + chr(34) + "b" + chr(34) + " : 2  }"
let minified = cJSON_Minify(spaced)
assert_eq(minified, "{" + chr(34) + "a" + chr(34) + ":1," + chr(34) + "b" + chr(34) + ":2}", "minify")

# ============================================================================
# Test 16: Version
# ============================================================================
print "--- Test 16: Version ---"
assert_eq(cJSON_Version(), "1.7.18-sage", "version string")

# ============================================================================
# Test 17: cJSON_ToSage and cJSON_FromSage
# ============================================================================
print "--- Test 17: ToSage / FromSage ---"
let ts_str = "{" + chr(34) + "name" + chr(34) + ":" + chr(34) + "Bob" + chr(34) + "," + chr(34) + "age" + chr(34) + ":25," + chr(34) + "tags" + chr(34) + ":[" + chr(34) + "a" + chr(34) + "," + chr(34) + "b" + chr(34) + "]}"
let ts_root = cJSON_Parse(ts_str)
let native = cJSON_ToSage(ts_root)
assert_eq(native["name"], "Bob", "ToSage name")
assert_eq(native["age"], 25, "ToSage age")
assert_eq(len(native["tags"]), 2, "ToSage tags length")
assert_eq(native["tags"][0], "a", "ToSage tags[0]")

# FromSage roundtrip
let back = cJSON_FromSage(native)
assert_true(cJSON_IsObject(back), "FromSage is object")
assert_eq(cJSON_GetStringValue(cJSON_GetObjectItem(back, "name")), "Bob", "FromSage name")

# ============================================================================
# Test 18: ParseWithLength
# ============================================================================
print "--- Test 18: ParseWithLength ---"
let pwl = "{" + chr(34) + "x" + chr(34) + ":1}extra_junk"
let pwl_node = cJSON_ParseWithLength(pwl, 7)
assert_true(pwl_node != nil, "ParseWithLength non-nil")

# ============================================================================
# Test 19: CreateIntArray / CreateStringArray
# ============================================================================
print "--- Test 19: CreateIntArray / CreateStringArray ---"
let ia = cJSON_CreateIntArray([10, 20, 30])
assert_eq(cJSON_GetArraySize(ia), 3, "int array size")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(ia, 1)), 20, "int array[1]")

let sa = cJSON_CreateStringArray(["x", "y", "z"])
assert_eq(cJSON_GetArraySize(sa), 3, "string array size")
assert_eq(cJSON_GetStringValue(cJSON_GetArrayItem(sa, 2)), "z", "string array[2]")

# ============================================================================
# Test 20: Escape sequences in strings
# ============================================================================
print "--- Test 20: Escape sequences ---"
let esc_str = "{" + chr(34) + "msg" + chr(34) + ":" + chr(34) + "hello" + chr(92) + "nworld" + chr(34) + "}"
let esc = cJSON_Parse(esc_str)
let esc_val = cJSON_GetStringValue(cJSON_GetObjectItem(esc, "msg"))
assert_eq(esc_val, "hello" + chr(10) + "world", "newline escape")

# ============================================================================
# Test 21: Empty object and array
# ============================================================================
print "--- Test 21: Empty containers ---"
let eo = cJSON_Parse("{}")
assert_true(cJSON_IsObject(eo), "empty object is object")
assert_eq(cJSON_GetArraySize(eo), 0, "empty object size 0")

let ea = cJSON_Parse("[]")
assert_true(cJSON_IsArray(ea), "empty array is array")
assert_eq(cJSON_GetArraySize(ea), 0, "empty array size 0")

# ============================================================================
# Test 22: Nested array in object
# ============================================================================
print "--- Test 22: Nested array in object ---"
let nao = cJSON_CreateObject()
let naa = cJSON_AddArrayToObject(nao, "items")
cJSON_AddItemToArray(naa, cJSON_CreateString("first"))
cJSON_AddItemToArray(naa, cJSON_CreateString("second"))
let nao_str = cJSON_PrintUnformatted(nao)
let nao_back = cJSON_Parse(nao_str)
let items_arr = cJSON_GetObjectItem(nao_back, "items")
assert_eq(cJSON_GetArraySize(items_arr), 2, "nested array size")
assert_eq(cJSON_GetStringValue(cJSON_GetArrayItem(items_arr, 0)), "first", "nested arr[0]")

# ============================================================================
# Test 23: AddObjectToObject
# ============================================================================
print "--- Test 23: AddObjectToObject ---"
let parent = cJSON_CreateObject()
let child_obj = cJSON_AddObjectToObject(parent, "meta")
cJSON_AddStringToObject(child_obj, "version", "1.0")
let meta = cJSON_GetObjectItem(parent, "meta")
assert_true(cJSON_IsObject(meta), "meta is object")
assert_eq(cJSON_GetStringValue(cJSON_GetObjectItem(meta, "version")), "1.0", "nested obj value")

# ============================================================================
# Test 24: Numbers - negative, float, scientific
# ============================================================================
print "--- Test 24: Number formats ---"
let nums = cJSON_Parse("[-5, 3.14, 1e3, -2.5e-1]")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(nums, 0)), -5, "negative int")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(nums, 1)), 3.14, "float")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(nums, 2)), 1000, "scientific")
assert_eq(cJSON_GetNumberValue(cJSON_GetArrayItem(nums, 3)), -0.25, "negative scientific")

# ============================================================================
# Test 25: Delete (no-op but should not crash)
# ============================================================================
print "--- Test 25: Delete ---"
let del = cJSON_CreateObject()
cJSON_AddStringToObject(del, "temp", "data")
cJSON_Delete(del)
passed = passed + 1

# ============================================================================
# Results
# ============================================================================
print ""
print "========================================="
print "cJSON Test Results: " + str(passed) + " passed, " + str(failed) + " failed"
print "========================================="
if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "ALL TESTS PASSED"
