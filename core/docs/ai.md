# ai.md — SageLang AI Quick Reference

SageLang is a Python-inspired, indentation-based systems language. Prefer valid Sage syntax over Python syntax when generating code.

## Core Syntax

```sage
let x = 10
var y = 20

proc add(a, b):
    return a + b

if x < y:
    print "x is smaller"
elif x == y:
    print "equal"
else:
    print "y is smaller"

while x < 100:
    x = x + 1

for item in items:
    print item
```

Blocks use indentation and `:`. Do not use `{}` for code blocks. `let`/`var` declare bindings; `proc` declares functions.

## Values

```text
number   string   bool   nil
array    dict     tuple
function class    instance
generator
```

Literals:

```sage
42
3.14
"hello"
true
false
nil

[1, 2, 3]
{"name": "Sage", "version": 4}
(1, 2, 3)
```

Indexing and slicing:

```sage
arr[0]
arr[1:4]
d["key"]
text[0]
```

## Functions

```sage
proc greet(name):
    print "Hello, " + name

proc add(a, b):
    return a + b
```

Functions are first-class and support closures:

```sage
proc make_counter():
    let count = 0

    proc inc():
        count = count + 1
        return count

    return inc
```

Anonymous procedures are supported:

```sage
let square = proc(x):
    return x * x
```

## Classes

```sage
class Animal:
    proc init(name):
        self.name = name

    proc speak():
        return self.name

class Dog(Animal):
    proc bark():
        return self.name + " says woof"

let d = Dog("Rex")
print d.bark()
```

Use:

```sage
self.field
self.method()
super.method()
```

## Exceptions

```sage
try:
    raise "oops"
catch e:
    print e
finally:
    print "done"
```

Other control flow:

```sage
return value
break
continue
yield value
defer:
    cleanup()
```

## Imports

```sage
import math
import crypto as c
from string import upper, lower
from module import thing as alias
```

Modules are normally `.sage` files.

## Operators

```text
+  -  *  /  %
== != < > <= >=
and or not
& | ^ ~ << >>
=
```

`and` / `or` are boolean-producing logical operators.

Unary operators:

```sage
-x
not x
~x
```

## Common Builtins

```sage
print value
str(value)
tonumber(value)
int(value)
len(value)
type(value)

push(array, value)
pop(array)
range(n)
range(start, end)

dict_keys(d)
dict_values(d)
dict_has(d, key)
dict_delete(d, key)

upper(s)
lower(s)
strip(s)
startswith(s, prefix)
endswith(s, suffix)
contains(s, value)
indexof(s, value)
```

## Strings

Use normal quoted strings:

```sage
let name = "Sage"
let msg = "Hello, " + name
```

String concatenation with non-strings is supported through value-to-string conversion in `+` when one operand is a string.

## Writing Sage Correctly

Prefer:

```sage
let total = 0

proc sum(values):
    let total = 0
    for value in values:
        total = total + value
    return total
```

Avoid assuming Sage is Python. In particular:

```text
No def
No import-from Python syntax assumptions
No {} code blocks
No semicolon-based block syntax
No Python classes/decorators unless Sage explicitly supports them
```

Use Sage keywords and syntax exactly as defined by the language.

## Runtime Model

Sage uses lexical scoping and first-class functions. A function captures its defining environment.

Conceptually:

```text
function
├── name
├── parameters
├── body
└── closure
```

Runtime execution may use the AST interpreter, CPC, bytecode VM, JIT, or AOT/native backends. Generated Sage should be backend-independent and rely only on documented language semantics.

## AI Generation Rules

1. Generate idiomatic indentation-based Sage.
2. Use `let` for normal declarations and `var` where mutable binding semantics require it.
3. Use `proc`, not `def`.
4. Preserve explicit `:` after `if`, `while`, `for`, `proc`, `class`, `try`, `catch`, `finally`, etc.
5. Do not invent Python standard-library modules or APIs.
6. Prefer existing Sage builtins and modules.
7. Keep code deterministic unless host APIs are explicitly requested.
8. When uncertain about a feature, inspect the Sage parser/AST/runtime implementation rather than guessing.
9. Treat `.sage` source as the source of truth for self-hosted compiler/runtime behavior.
10. Keep generated code compatible with both `sage` and `sage-c` whenever possible.

## Minimal Program

```sage
proc main():
    let values = [1, 2, 3, 4, 5]
    let total = 0

    for value in values:
        total = total + value

    print "sum = " + str(total)

main()
```

## Canonical Mental Model

```text
Sage source
    ↓
Lexer
    ↓
Parser
    ↓
AST
    ↓
Semantic analysis
    ↓
Execution backend
    ↓
Common Sage runtime
```

When generating or modifying Sage, preserve this principle:

> One Sage language, one semantic model, multiple execution backends.
