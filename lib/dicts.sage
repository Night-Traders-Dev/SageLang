proc keys(dict):
    return dict_keys(dict)

proc values(dict):
    return dict_values(dict)

proc size(dict):
    return len(dict_keys(dict))

proc has(dict, key):
    return dict_has(dict, key)

proc get_or(dict, key, fallback):
    if dict_has(dict, key):
        return dict[key]
    return fallback

proc entries(dict):
    let result = []
    let key_list = dict_keys(dict)
    for key in key_list:
        push(result, (key, dict[key]))
    return result

proc has_all(dict, key_list):
    for key in key_list:
        if dict_has(dict, key) == false:
            return false
    return true

proc has_any(dict, key_list):
    for key in key_list:
        if dict_has(dict, key):
            return true
    return false

proc select_values(dict, key_list, fallback):
    let result = []
    for key in key_list:
        if dict_has(dict, key):
            push(result, dict[key])
        else:
            push(result, fallback)
    return result

proc remove_keys(dict, key_list):
    for key in key_list:
        if dict_has(dict, key):
            dict_delete(dict, key)
    return dict

proc count_missing(dict, key_list):
    let missing = 0
    for key in key_list:
        if dict_has(dict, key) == false:
            missing = missing + 1
    return missing
