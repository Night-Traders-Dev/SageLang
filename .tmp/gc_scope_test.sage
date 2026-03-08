proc keep():
    let items = [1, 2, 3]
    gc_collect()
    print items[1]
keep()
