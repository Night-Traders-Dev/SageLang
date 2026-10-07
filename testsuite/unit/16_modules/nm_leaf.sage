## Reached through nm_lib rather than directly from the entry program, so __name__
## has to be right for a module that is not a first-level import too.
proc leaf_name() -> String:
    return __name__
