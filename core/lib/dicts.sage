# dicts.sage — Dictionary utilities
# Thin wrappers over native dict ops marked @inline.

@inline
proc keys(dict):
    return dict_keys(dict)

@inline
proc values(dict):
    return dict_values(dict)

## Returns the number of entries in the dictionary.
## Optimization: Use native len(dict) which is O(1) instead of len(dict_keys(dict)) which is O(N).
@inline
proc size(dict):
    return len(dict)

@inline
proc has(dict, key):
    return dict_has(dict, key)

@inline
proc get_or(dict, key, fallback):
    if dict_has(dict, key):
        return dict[key]
    return fallback

## Returns key-value pairs as a list of 2-tuples.
## Optimization: Uses direct 'for key in dict' iteration to avoid allocating
## an intermediate array via 'dict_keys(dict)'.
proc entries(dict):
    let result = []
    for key in dict:
        push(result, (key, dict[key]))
    return result

## Checks if all keys in key_list are present in the dictionary.
@inline
proc has_all(dict, key_list):
    for key in key_list:
        if dict_has(dict, key) == false:
            return false
    return true

## Checks if any key in key_list is present in the dictionary.
@inline
proc has_any(dict, key_list):
    for key in key_list:
        if dict_has(dict, key):
            return true
    return false

## Returns array of values corresponding to key_list, using fallback when key is absent.
@inline
proc select_values(dict, key_list, fallback):
    let result = []
    for key in key_list:
        if dict_has(dict, key):
            push(result, dict[key])
        else:
            push(result, fallback)
    return result

## Removes all specified keys from the dictionary.
@inline
proc remove_keys(dict, key_list):
    for key in key_list:
        if dict_has(dict, key):
            dict_delete(dict, key)
    return dict

## Returns the count of keys from key_list missing in the dictionary.
@inline
proc count_missing(dict, key_list):
    let missing = 0
    for key in key_list:
        if dict_has(dict, key) == false:
            missing = missing + 1
    return missing
