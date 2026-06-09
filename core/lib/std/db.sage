gc_disable()
# In-memory database with SQL-like query operations
# Provides tables, insert, select, update, delete, join, aggregate

# ============================================================================
# Table creation
# ============================================================================

proc create_table(name, columns):
    let t = {}
    t["name"] = name
    t["columns"] = columns
    t["rows"] = []
    t["auto_id"] = 1
    t["indexes"] = {}
    return t

# ============================================================================
# CRUD operations
# ============================================================================

proc insert(table, row):
    if not dict_has(row, "id"):
        row["id"] = table["auto_id"]
        table["auto_id"] = table["auto_id"] + 1
    push(table["rows"], row)
    return row["id"]

proc insert_many(table, rows):
    let ids = []
    for i in range(len(rows)):
        push(ids, insert(table, rows[i]))
    return ids

# Select rows matching a predicate
proc select(table, predicate):
    let result = []
    let rows = table["rows"]
    for i in range(len(rows)):
        if predicate(rows[i]):
            push(result, rows[i])
    return result

# Select all rows
proc select_all(table):
    return table["rows"]

# Select first matching row
proc find_one(table, predicate):
    let rows = table["rows"]
    for i in range(len(rows)):
        if predicate(rows[i]):
            return rows[i]
    return nil

# Find by id
proc find_by_id(table, id):
    let rows = table["rows"]
    for i in range(len(rows)):
        if rows[i]["id"] == id:
            return rows[i]
    return nil

# Update rows matching predicate
proc update(table, predicate, updates):
    let count = 0
    let rows = table["rows"]
    let keys = dict_keys(updates)
    for i in range(len(rows)):
        if predicate(rows[i]):
            for j in range(len(keys)):
                rows[i][keys[j]] = updates[keys[j]]
            count = count + 1
    return count

# Delete rows matching predicate
proc delete(table, predicate):
    let new_rows = []
    let deleted = 0
    let rows = table["rows"]
    for i in range(len(rows)):
        if predicate(rows[i]):
            deleted = deleted + 1
        else:
            push(new_rows, rows[i])
    table["rows"] = new_rows
    return deleted

# ============================================================================
# Query operations
# ============================================================================

# Select specific columns
proc project(rows, columns):
    let result = []
    for i in range(len(rows)):
        let row = {}
        for j in range(len(columns)):
            let col = columns[j]
            if dict_has(rows[i], col):
                row[col] = rows[i][col]
        push(result, row)
    return result

# Order by a column (ascending)
proc order_by(rows, column):
    # Insertion sort
    let arr = []
    for i in range(len(rows)):
        push(arr, rows[i])
    let n = len(arr)
    for i in range(n):
        let j = i
        while j > 0:
            if arr[j - 1][column] > arr[j][column]:
                let temp = arr[j]
                arr[j] = arr[j - 1]
                arr[j - 1] = temp
            j = j - 1
    return arr

# Order by descending
proc order_by_desc(rows, column):
    let sorted = order_by(rows, column)
    let result = []
    let i = len(sorted) - 1
    while i >= 0:
        push(result, sorted[i])
        i = i - 1
    return result

# Limit results
proc limit(rows, n):
    let result = []
    let count = n
    if count > len(rows):
        count = len(rows)
    for i in range(count):
        push(result, rows[i])
    return result

# Offset + limit (pagination)
proc paginate(rows, page, page_size):
    let start = page * page_size
    let result = []
    let i = start
    while i < start + page_size and i < len(rows):
        push(result, rows[i])
        i = i + 1
    return result

# Count rows
proc count(table):
    return len(table["rows"])

# Count matching rows
proc count_where(table, predicate):
    let c = 0
    let rows = table["rows"]
    for i in range(len(rows)):
        if predicate(rows[i]):
            c = c + 1
    return c

# ============================================================================
# Aggregation
# ============================================================================

proc sum_col(rows, column):
    let s = 0
    for i in range(len(rows)):
        if dict_has(rows[i], column):
            s = s + rows[i][column]
    return s

proc avg_col(rows, column):
    if len(rows) == 0:
        return 0
    return sum_col(rows, column) / len(rows)

proc min_col(rows, column):
    if len(rows) == 0:
        return nil
    let m = rows[0][column]
    for i in range(len(rows)):
        if rows[i][column] < m:
            m = rows[i][column]
    return m

proc max_col(rows, column):
    if len(rows) == 0:
        return nil
    let m = rows[0][column]
    for i in range(len(rows)):
        if rows[i][column] > m:
            m = rows[i][column]
    return m

# Group by a column
proc group_by(rows, column):
    let groups = {}
    for i in range(len(rows)):
        let key = str(rows[i][column])
        if not dict_has(groups, key):
            groups[key] = []
        push(groups[key], rows[i])
    return groups

# Distinct values in a column
proc distinct(rows, column):
    let seen = {}
    let result = []
    for i in range(len(rows)):
        let val = str(rows[i][column])
        if not dict_has(seen, val):
            seen[val] = true
            push(result, rows[i][column])
    return result

# ============================================================================
# Joins
# ============================================================================

# Inner join two result sets on a key
proc inner_join(left, right, left_key, right_key):
    let result = []
    for i in range(len(left)):
        for j in range(len(right)):
            if left[i][left_key] == right[j][right_key]:
                let merged = {}
                let lkeys = dict_keys(left[i])
                for k in range(len(lkeys)):
                    merged[lkeys[k]] = left[i][lkeys[k]]
                let rkeys = dict_keys(right[j])
                for k in range(len(rkeys)):
                    if not dict_has(merged, rkeys[k]):
                        merged[rkeys[k]] = right[j][rkeys[k]]
                push(result, merged)
    return result
