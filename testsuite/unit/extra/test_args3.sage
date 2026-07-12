# EXPECT: 2
# EXPECT: true
# EXPECT: test_args3.sage
import sys
let a = sys.args()
print len(a)
if len(a) > 0:
    let bin_path = a[0]
    let path_len = len(bin_path)
    print slice(bin_path, path_len - 4, path_len) == "sage"
end
if len(a) > 1:
    print a[1]
end
