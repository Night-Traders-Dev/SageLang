## Fixture for module_default_args.sage: procedures with defaulted parameters,
## reached only across a module boundary.

proc chain(a: Int, b: Int = a * 2, c: Int = b + 1) -> Int:
    return a * 100 + b * 10 + c

proc mixed(a: Int, b: Int = 5, c: String = "z") -> String:
    return str(a) + str(b) + c

proc keywordish(a: Int, b: Int = 2) -> Int:
    return a * b

## A default computed from another default: 3 -> b 6 -> c 36.
proc derived(a: Int, b: Int = a * 2, c: Int = b * b) -> Int:
    return c

## No defaults at all, so calling it short must still be an error.
proc needs_two(a: Int, b: Int) -> Int:
    return a - b
