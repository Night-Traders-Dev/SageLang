# Comprehensive dictionary operations demo
print "=== Dictionary Operations Demo ==="
print ""

# Create a dictionary
print "1. Creating a dictionary:"
let person = {"name": "Alice", "age": "30", "city": "NYC"}
print "Person dictionary created"

print ""
print "2. Accessing values:"
print "Name:"
print person["name"]
print "Age:"
print person["age"]
print "City:"
print person["city"]

print ""
print "3. Adding new key-value pairs:"
person["job"] = "Engineer"
person["country"] = "USA"
print "Added job and country"

print ""
print "4. Get all keys:"
let keys = dict_keys(person)
print "Keys:"
for key in keys:
    print key

print ""
print "5. Get all values:"
let values = dict_values(person)
print "Values:"
for val in values:
    print val

print ""
print "6. Check if key exists:"
if dict_has(person, "name"):
    print "'name' key exists"

if dict_has(person, "phone"):
    print "'phone' key exists"
else:
    print "'phone' key does not exist"

print ""
print "7. Delete a key:"
dict_delete(person, "country")
print "Deleted 'country' key"

print ""
print "8. Final keys after deletion:"
let final_keys = dict_keys(person)
for key in final_keys:
    print key

print ""
print "Dictionary operations complete!"