## Library side of the __name__ test.
import nm_leaf
proc who_am_i() -> String:
    return __name__
proc leaf_name() -> String:
    return nm_leaf.leaf_name()
