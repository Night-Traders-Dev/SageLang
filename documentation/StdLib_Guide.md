# SageLang Standard Library Guide (`lib/std/`)

The standard library provides 23 modules covering core utilities, type system extensions, concurrency primitives, and developer tooling. All imported with the `std.` prefix.

---

## Regular Expressions (`std.regex`)

```sage
import std.regex

# Search for a pattern
let m = regex.search("[0-9]+", "order #12345")
print m["text"]    # 12345
print m["start"]   # 7

# Full match
print regex.full_match("[a-z]+", "hello")  # true

# Find all matches
let matches = regex.find_all("[a-z]+", "hello world foo")
print len(matches)  # 3

# Replace
print regex.replace_all("[0-9]", "a1b2c3", "X")  # aXbXcX

# Split
let parts = regex.split_by(",", "a,b,c")
print len(parts)  # 3
```

Supported patterns: `.` `*` `+` `?` `[abc]` `[^abc]` `[a-z]` `^` `$` `\d` `\D` `\w` `\W` `\s` `\S`

---

## Date & Time (`std.datetime`)

```sage
import std.datetime

let dt = datetime.create(2024, 3, 15, 10, 30, 0)
print datetime.to_iso(dt)          # 2024-03-15T10:30:00
print datetime.weekday_name(dt)    # Friday

let tomorrow = datetime.add_days(dt, 1)
let parsed = datetime.parse_iso("2024-12-25T00:00:00")
print datetime.diff_days(parsed, dt)

print datetime.is_leap_year(2024)  # true
```

---

## Logging (`std.log`)

```sage
import std.log

let logger = log.create("myapp", log.INFO)
log.info(logger, "Server started")
log.error(logger, "Connection failed")

# With structured fields
let fields = {"port": 8080, "host": "0.0.0.0"}
log.info_f(logger, "Listening", fields)

# Child logger with inherited fields
log.with_field(logger, "service", "api")
let child = log.child(logger, "handler")
```

---

## CLI Argument Parsing (`std.argparse`)

```sage
import std.argparse

let parser = argparse.create("myapp", "A CLI tool")
argparse.add_flag(parser, "verbose", "v", "Verbose output")
argparse.add_option(parser, "output", "o", "Output file", "out.txt")
argparse.add_positional(parser, "input", "Input file", true)

let result = argparse.parse(parser, sys.args)
if argparse.get_flag(result, "verbose"):
    print "Verbose mode"
let output = argparse.get_option(result, "output")
```

---

## Compression (`std.compress`)

```sage
import std.compress

# RLE
let encoded = compress.rle_encode([1,1,1,2,2,3])
let decoded = compress.rle_decode(encoded)

# LZ77
let data = compress.str_to_bytes("abcabcabcabc")
let lz = compress.lz77_encode(data, 64)
let original = compress.lz77_decode(lz)

# Delta encoding (good for sorted data)
let deltas = compress.delta_encode([10, 12, 15, 20])
let restored = compress.delta_decode(deltas)
```

---

## String Formatting (`std.fmt`)

```sage
import std.fmt

print fmt.to_hex(255, 4)            # 0x00ff
print fmt.to_bin(42, 8)             # 0b00101010
print fmt.format_int(1000000)        # 1,000,000
print fmt.format_float(3.14159, 2)   # 3.14
print fmt.format_pct(0.425, 1)       # 42.5%
print fmt.format_bytes(1572864)      # 1.5 MB
print fmt.format_duration(0.003)     # 3.0ms

# Template formatting
print fmt.template("Hello, {name}!", {"name": "World"})

# Table formatting
let headers = ["Name", "Age"]
let rows = [["Alice", 30], ["Bob", 25]]
print fmt.table(headers, rows)
```

---

## Unicode & Strings (`std.unicode`)

```sage
import std.unicode

print unicode.to_upper("hello")          # HELLO
print unicode.to_title("hello world")    # Hello World
print unicode.trim("  hello  ")          # hello
print unicode.center("hi", 10, "-")      # ----hi----
print unicode.reverse("hello")           # olleh
print unicode.starts_with("hello", "he") # true
print unicode.is_alpha("A")             # true
print unicode.is_digit("5")             # true

# UTF-8 encoding
let bytes = unicode.encode_codepoint(8364)  # Euro sign
```

---

## Testing Framework (`std.testing`)

```sage
import std.testing

let suite = testing.create_suite("Math Tests")

proc test_add():
    testing.assert_equal(1 + 1, 2, "basic addition")
    testing.assert_greater(5, 3, "5 > 3")

proc test_string():
    testing.assert_contains("hello world", "world", "substring")
    testing.assert_raises(proc(): raise "boom", "should throw")

testing.add_test(suite, "addition", test_add)
testing.add_test(suite, "string ops", test_string)
testing.run(suite)
testing.report(suite)
```

---

## Enums, Result, Option (`std.enum`)

```sage
import std.enum

# Define an enum
let Color = enum.enum_def("Color", ["Red", "Green", "Blue"])
let red = enum.variant(Color, "Red")
print enum.is_variant(red, "Red")  # true

# Result type
let ok = enum.ok(42)
let err = enum.err("not found")
print enum.unwrap(ok)              # 42
print enum.unwrap_or(err, 0)      # 0
print enum.is_ok(ok)              # true

# Option type
let val = enum.some(10)
let empty = enum.none()
print enum.unwrap_option(val)      # 10
print enum.is_none(empty)         # true
```

---

## Traits / Interfaces (`std.trait`)

```sage
import std.trait

let Printable = trait.define("Printable", ["to_string"])

let obj = {"to_string": "hello"}
print trait.implements(obj, Printable)  # true

# Functional utilities
let nums = [1, 2, 3, 4, 5]
let evens = trait.trait_filter(nums, proc(x): return (x & 1) == 0)
let doubled = trait.trait_map(nums, proc(x): return x * 2)
print trait.any(nums, proc(x): return x > 4)  # true
print trait.all(nums, proc(x): return x > 0)  # true
```

---

## Channels (`std.channel`)

```sage
import std.channel

let ch = channel.buffered(10)
channel.send(ch, "hello")
channel.send(ch, "world")
print channel.recv(ch)        # hello
print channel.pending(ch)     # 1

# Select across multiple channels
let ch1 = channel.buffered(5)
let ch2 = channel.buffered(5)
channel.send(ch1, 42)
let result = channel.select([ch1, ch2])
print result["value"]         # 42

# Drain all values
let vals = channel.drain(ch)
```

---

## Thread Pool (`std.threadpool`)

```sage
import std.threadpool

proc square(x):
    return x * x

let pool = threadpool.create(4)
let id = threadpool.submit(pool, square, [7])
threadpool.run_all(pool)
print threadpool.get_result(pool, id)  # 49

# Parallel map
let results = threadpool.parallel_map(pool, square, [1, 2, 3, 4])
```

---

## Atomic Operations (`std.atomic`)

```sage
import std.atomic

let counter = atomic.atomic_int(0)
atomic.increment(counter)
atomic.add(counter, 10)
print atomic.load(counter)          # 11
print atomic.cas(counter, 11, 20)   # true (swapped)
print atomic.load(counter)          # 20
```

---

## In-Memory Database (`std.db`)

```sage
import std.db

let users = db.create_table("users", ["id", "name", "age"])
db.insert(users, {"name": "Alice", "age": 30})
db.insert(users, {"name": "Bob", "age": 25})

let older = db.select(users, proc(r): return r["age"] > 27)
let sorted = db.order_by(db.select_all(users), "name")
let avg_age = db.avg_col(db.select_all(users), "age")
let groups = db.group_by(db.select_all(users), "age")
```

---

## Profiler (`std.profiler`)

```sage
import std.profiler

let p = profiler.create()
profiler.begin(p, "load_data")
# ... work ...
profiler.end_section(p, "load_data")
print profiler.report(p)

# Benchmark
let result = profiler.bench("sort", my_sort_fn, 1000)
print result["ops_per_second"]
```

---

## Build Configuration (`std.build`)

```sage
import std.build

let proj = build.create_project("myapp", "1.0.0")
build.set_description(proj, "My application")
build.add_dep(proj, "json", ">=1.0")
build.add_target(proj, "main", "executable", ["main.sage"])
print build.to_string(proj)

let v = build.parse_version("1.5.3")
let next = build.bump_minor(v)
print next["string"]  # 1.6.0
```

---

## Module Reference

| Module | Import | Key Functions |
|--------|--------|---------------|
| `regex` | `import std.regex` | `search`, `full_match`, `test`, `find_all`, `replace_all`, `split_by`, `compile` |
| `datetime` | `import std.datetime` | `create`, `to_iso`, `parse_iso`, `add_days`, `diff_seconds`, `weekday_name`, `is_leap_year` |
| `log` | `import std.log` | `create`, `info`, `error`, `warn`, `debug`, `fatal`, `add_handler`, `child`, `with_field` |
| `argparse` | `import std.argparse` | `create`, `add_flag`, `add_option`, `parse`, `get_flag`, `get_option`, `help_text` |
| `compress` | `import std.compress` | `rle_encode`, `rle_decode`, `lz77_encode`, `lz77_decode`, `delta_encode`, `delta_decode` |
| `process` | `import std.process` | `platform`, `args`, `get_env`, `exit_with`, `basename`, `dirname`, `extension`, `join_path` |
| `unicode` | `import std.unicode` | `to_upper`, `to_lower`, `to_title`, `trim`, `center`, `reverse`, `encode_codepoint`, `is_alpha` |
| `fmt` | `import std.fmt` | `to_hex`, `format_int`, `format_float`, `format_bytes`, `template`, `table`, `join` |
| `testing` | `import std.testing` | `create_suite`, `add_test`, `run`, `report`, `assert_equal`, `assert_contains`, `benchmark` |
| `enum` | `import std.enum` | `enum_def`, `variant`, `ok`, `err`, `some`, `none`, `unwrap`, `is_ok`, `map_result` |
| `trait` | `import std.trait` | `define`, `implements`, `dispatch`, `trait_filter`, `trait_map`, `all`, `any` |
| `signal` | `import std.signal` | `create_bus`, `on`, `once`, `emit`, `off`, `event_names`, `atexit` |
| `db` | `import std.db` | `create_table`, `insert`, `select`, `update`, `delete`, `order_by`, `group_by`, `inner_join` |
| `channel` | `import std.channel` | `buffered`, `send`, `recv`, `select`, `drain`, `close`, `pending`, `try_send` |
| `threadpool` | `import std.threadpool` | `create`, `submit`, `run_all`, `get_result`, `parallel_map`, `pool_stats` |
| `atomic` | `import std.atomic` | `atomic_int`, `load`, `store`, `add`, `cas`, `exchange`, `increment`, `create_spinlock` |
| `rwlock` | `import std.rwlock` | `create`, `read_lock`, `write_lock`, `try_read_lock`, `with_read`, `with_write` |
| `condvar` | `import std.condvar` | `create`, `wait`, `notify`, `notify_all`, `create_barrier`, `create_semaphore`, `acquire` |
| `debug` | `import std.debug` | `inspect`, `dump`, `trace`, `assert_msg`, `create_watcher`, `watch`, `time_it`, `memory_snapshot` |
| `profiler` | `import std.profiler` | `create`, `begin`, `end_section`, `profile`, `report`, `hotspots`, `bench` |
| `docgen` | `import std.docgen` | `extract_docs`, `to_markdown`, `split_lines` |
| `build` | `import std.build` | `create_project`, `add_dep`, `add_target`, `parse_version`, `bump_major`, `to_string` |
| `interop` | `import std.interop` | `load_library`, `bind`, `call`, `pack_i32`, `unpack_i32`, `lib_path`, `define_struct` |
