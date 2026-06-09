# -----------------------------------------
# ffi_point_distance.sage
# -----------------------------------------

# Define a C-compatible struct: { double x; double y; }
let Point = struct_def([["x", "double"], ["y", "double"]])

proc point_new(x, y):
    let p = struct_new(Point)
    struct_set(p, Point, "x", x)
    struct_set(p, Point, "y", y)
    return p

proc point_distance_from_origin(p, libm):
    let x = struct_get(p, Point, "x")
    let y = struct_get(p, Point, "y")
    let r2 = x * x + y * y
    let dist = ffi_call(libm, "sqrt", "double", [r2])
    return dist

proc main():
    let libm = ffi_open("libm.so.6")
    if libm == nil:
        print "Failed to open libm"
        return

    let p1 = point_new(3.0, 4.0)
    let p2 = point_new(5.0, 12.0)

    let d1 = point_distance_from_origin(p1, libm)
    let d2 = point_distance_from_origin(p2, libm)

    print "Point 1 distance = " + str(d1)
    print "Point 2 distance = " + str(d2)

    mem_free(p1)
    mem_free(p2)
    ffi_close(libm)

main()
