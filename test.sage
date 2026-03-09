proc endswith(a, b):
    let test = split(a, "")
    if test[len(test) - 1] == b:
        return true
    else:
        return false



let test = endswith("hello", "o")
print test
