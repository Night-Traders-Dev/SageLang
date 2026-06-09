gc_disable()
# EXPECT: 3
# EXPECT: Alice
# EXPECT: 2
# EXPECT: 1
# EXPECT: 60

import std.db

let users = db.create_table("users", ["id", "name", "age"])

let r1 = {}
r1["name"] = "Alice"
r1["age"] = 30

let r2 = {}
r2["name"] = "Bob"
r2["age"] = 25

let r3 = {}
r3["name"] = "Charlie"
r3["age"] = 35

db.insert(users, r1)
db.insert(users, r2)
db.insert(users, r3)

print db.count(users)

# Find one
proc name_is_alice(row):
    return row["name"] == "Alice"

let alice = db.find_one(users, name_is_alice)
print alice["name"]

# Select with predicate
proc age_over_27(row):
    return row["age"] > 27

let older = db.select(users, age_over_27)
print len(older)

# Delete
let deleted = db.delete(users, name_is_alice)
print deleted

# Aggregation
print db.sum_col(db.select_all(users), "age")
