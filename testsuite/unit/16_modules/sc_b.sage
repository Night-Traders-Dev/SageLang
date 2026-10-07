proc helper() -> String:
    return "from b"

proc outer() -> String:
    return "b.outer calls " + helper()
