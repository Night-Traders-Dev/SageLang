import strings

class _String:
    proc substr(s, st, l):
        return string_substr(s, st, l)
    proc contains(s, p):
        return contains(s, p)
let string = _String()
