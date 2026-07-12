# EXPECT: linux
# EXPECT: true
# Test sys module info
import sys
import io

print sys.platform

let version_path = "VERSION"
if not io.exists(version_path):
    version_path = "../VERSION"
end

let expected_version = io.readfile(version_path)
let clean_version = ""
for i in range(len(expected_version)):
    let c = expected_version[i]
    if c != "\n" and c != "\r" and c != " " and c != "\t":
        clean_version = clean_version + c
    end
end

print sys.version == clean_version
