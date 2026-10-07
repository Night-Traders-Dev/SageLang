## Module proc scoping test: this module and sc_b both define helper(), and outer()
## calls it unqualified.
proc helper() -> String:
    return "from a"

proc outer() -> String:
    return "a.outer calls " + helper()
