# -----------------------------------------
# doc_store.sage
# -----------------------------------------

class Document:
    proc init(data):
        # data is a dict like {"name": "...", "age": 42, ...}
        self.data = data

    proc get(key):
        return self.data[key]

    proc set(key, value):
        self.data[key] = value

    proc to_string():
        let keys = dict_keys(self.data)
        let parts = []
        for k in keys:
            let v = self.data[k]
            push(parts, k + "=" + str(v))
        return "Document(" + join(parts, ", ") + ")"

class Collection:
    proc init(name):
        self.name = name
        self.docs = []

    proc insert(doc):
        push(self.docs, doc)

    # filter_proc is a proc taking (doc) -> bool.
    proc find(filter_proc):
        let result = []
        for d in self.docs:
            if filter_proc(d):
                push(result, d)
        return result

    proc all():
        return self.docs

# Higher-order helpers to build filter procs via closures.

proc older_than(age_limit):
    proc check(doc):
        return doc.get("age") > age_limit
    return check

proc in_city(city_name):
    proc check(doc):
        return doc.get("city") == city_name
    return check

proc and_filter(f1, f2):
    proc check(doc):
        return f1(doc) and f2(doc)
    return check

proc main():
    let people = Collection("people")

    people.insert(Document({"name": "Alice", "age": 30, "city": "NYC"}))
    people.insert(Document({"name": "Bob",   "age": 45, "city": "NYC"}))
    people.insert(Document({"name": "Cara",  "age": 25, "city": "SF"}))
    people.insert(Document({"name": "Dan",   "age": 50, "city": "NYC"}))

    print "All documents:"
    for d in people.all():
        print d.to_string()

    print ""
    print "People older than 40:"
    let q1 = older_than(40)
    let res1 = people.find(q1)
    for d in res1:
        print d.to_string()

    print ""
    print "People in NYC and older than 30:"
    let q_city = in_city("NYC")
    let q_age  = older_than(30)
    let q_both = and_filter(q_city, q_age)
    let res2 = people.find(q_both)
    for d in res2:
        print d.to_string()

main()
