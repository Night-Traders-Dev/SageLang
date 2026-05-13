# Sage Android Guide

Build native Android apps in Sage with dramatically less code than traditional Kotlin/XML development.

## Quick Start

Write your app in Sage:

```sage
# hello.sage
let name = "World"
print("Hello, " + name + "!")

proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

print("5! = " + str(factorial(5)))
```

Generate an Android project:

```bash
sage --compile-android hello.sage -o hello_app \
     --package com.example.hello \
     --app-name "Hello Sage"
```

Build and install:

```bash
cd hello_app
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

## CLI Reference

### `--emit-kotlin`

Transpile Sage to Kotlin source code:

```bash
sage --emit-kotlin input.sage [-o output.kt] [-O0..3]
```

### `--compile-android`

Generate a complete Android project:

```bash
sage --compile-android input.sage [-o output_dir] [options]
```

Options:
- `--package com.example.app` — Android package name (default: `com.sage.app`)
- `--app-name "My App"` — Display name (default: `SageApp`)
- `--min-sdk 24` — Minimum Android API level (default: 24)
- `-O0` through `-O3` — Optimization level

### REPL

```
sage
> :emit-kotlin let x = 42
```

## Generated Project Structure

```
output_dir/
  build.gradle.kts          # Root Gradle config
  settings.gradle.kts       # Project settings
  gradle.properties          # Build properties
  app/
    build.gradle.kts         # App module config
    src/main/
      AndroidManifest.xml
      kotlin/
        com/example/app/
          Main.kt            # Transpiled Sage code
          MainActivity.kt    # Android launcher activity
        sage/runtime/
          SageRuntime.kt     # Sage runtime library
      res/values/
        strings.xml
        styles.xml
```

## Language Feature Mapping

| Sage | Kotlin |
|------|--------|
| `let x = 10` | `var x = S.num(10.0)` |
| `proc foo(a, b):` | `fun foo(a: SageVal, b: SageVal): SageVal` |
| `class Dog(Animal):` | `open class Dog : Animal()` |
| `if x > 0:` | `if (S.truthy(S.gt(x, S.num(0.0))))` |
| `for item in items:` | `for (item in S.toIterable(items))` |
| `match x:` | `when` chain with `S.equal()` |
| `try: ... catch e:` | `try { } catch (_e: SageException)` |
| `raise "error"` | `throw SageException(S.str("error"))` |
| `print(x)` | `S.printLn(x)` |
| `[1, 2, 3]` | `S.array(S.num(1.0), ...)` |
| `{"k": v}` | `S.dict("k" to v)` |
| `(a, b, c)` | `S.tuple(a, b, c)` |

## Runtime (SageRuntime.kt)

The runtime provides a dynamic value system through a sealed class hierarchy:

- `Value.Num(Double)` — numbers
- `Value.Str(String)` — strings
- `Value.Bool(Boolean)` — booleans
- `Value.Nil` — null
- `Value.Arr(MutableList)` — arrays
- `Value.Dict(MutableMap)` — dictionaries
- `Value.Tup(List)` — tuples
- `Value.Obj(SageObject)` — class instances
- `Value.Fn` — function values

All Sage operators and built-in functions are available through `SageRuntime` (aliased as `S`).

## Android UI Libraries

### `lib/android/app.sage`

High-level app framework:

```sage
import android.app

let my_app = App("My App")
my_app.package("com.example.app")
my_app.permission("INTERNET")

my_app.screen("home", proc(ctx):
    ctx.text("Welcome!")
    ctx.button("Click", proc():
        ctx.toast("Clicked!")
    )
)

my_app.launch()
```

### `lib/android/compose.sage`

Jetpack Compose-style declarative UI:

```sage
import android.compose

let counter = State(0)

let ui = Column()
ui.child(Text("Count: " + str(counter.get())))
ui.child(Button("+1", proc():
    counter.set(counter.get() + 1)
))
```

## Requirements

- Android SDK (API 24+)
- Gradle 8.x or Android Studio
- JDK 17+

## Advanced Features

### Type Specialization (-O2+)

At optimization level 2 or higher, the transpiler infers native Kotlin types for variables initialized with literals. `let x = 10` emits `var x: Double = 10.0` instead of `var x = S.num(10.0)`, eliminating boxing overhead.

### Generators

Sage generators transpile to Kotlin `sequence { }` blocks with native `yield()`:

```sage
proc count_up(n):
    let i = 0
    while i < n:
        yield i
        i = i + 1

for x in count_up(5):
    print(x)
```

### Async/Await (Coroutines)

Async procs emit as `suspend fun`, await uses `kotlinx.coroutines.runBlocking`:

```sage
async proc fetch():
    return 42

let result = await fetch()
```

### Memory Operations

`mem_alloc`/`mem_read`/`mem_write`/`mem_free` map to `java.nio.ByteBuffer`:

```sage
let buf = mem_alloc(256)
mem_write(buf, 0, "int", 42)
print(mem_read(buf, 0, "int"))
mem_free(buf)
```

### Jetpack Compose

When `import android.compose` is detected, the project generator emits a Compose-based Activity with Material 3, `@Composable` entry point, and all Compose dependencies.

## Remaining Limitations

- FFI `ffi_call` logs calls but cannot invoke arbitrary native functions without pre-declared JNI bindings
- `asm_exec`/`asm_compile` are no-ops on JVM (returns `"jvm"` for `asm_arch()`)
- Generator functions cannot yet be passed as first-class values (must be called directly in `for` loops)
- Type specialization is limited to simple literal assignments (no interprocedural inference)
