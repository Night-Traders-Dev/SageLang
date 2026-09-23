# CommonJS → ESM Transpiler (`cjs2esm`) — Architecture & Implementation Plan

## Project Overview

Build a standalone, high-performance **CommonJS (CJS) → ECMAScript Modules (ESM)** native transpiler written directly in **SageLang**, with a primary integration and compatibility benchmark focused on the **Discord.js ecosystem**.

The transpiler compiles via SageLang's C/LLVM backend into a self-contained native binary. It converts real-world Node.js/CommonJS codebases into clean, runnable ESM projects while strictly preserving runtime execution order, export/import semantics, object identity, and Node.js-specific conveniences (`__dirname`, `__filename`, `require.resolve()`, `require.main`).

---

## 1. Native SageLang Architecture

Implementing the transpiler in SageLang eliminates external runtime dependencies (such as Node.js, Python, or V8 engines) during the transformation process. The pipeline is architected around an AST-first, multi-pass design.

```text
Source File (.js/.cjs)
          |
          v
  +---------------+
  | SageLang      |   Lexical scanning (handles ASI, template strings, regex literals)
  | Lexer         |
  +-------+-------+
          |
          v
  +---------------+
  | SageLang      |   Recursive Descent + Pratt Expression Parser
  | ECMAScript    |   Constructs typed SageLang AST (ESTree-compliant classes)
  | Parser        |
  +-------+-------+
          |
          v
  +---------------+
  | Lexical Scope |   Resolves variable shadowing, alias chains, and
  | & CJS Analyzer|   module classification (PURE_CJS, DYNAMIC, etc.)
  +-------+-------+
          |
          v
  +---------------+
  | AST Transform |   Pattern matching passes: static imports, exports,
  | Pipeline      |   runtime shims, dynamic requires, JSON destructuring
  +-------+-------+
          |
          v
  +---------------+
  | Printer & VLQ |   Formats ESM output code and generates
  | Source Mapper |   standard Base64 VLQ Source Maps (.js.map)
  +---------------+
```

### 1.1 Engine Subsystems

1. **Native Lexer (`src/lexer/`)**:
   - Tokenizes ECMAScript syntax (ECMA-262 latest standard).
   - Tracks line, column, and byte offsets for source map generation.
   - Implements full Automatic Semicolon Insertion (ASI) rules.
   - Preserves comments (single-line, multi-line, JSDoc) and attaches them as leading/trailing trivia to adjacent AST nodes.

2. **Native AST Hierarchy (`src/ast/`)**:
   - Strongly typed SageLang classes reflecting ESTree standards (`Program`, `ImportDeclaration`, `ExportNamedDeclaration`, `CallExpression`, `Identifier`, `Literal`, etc.).
   - Base `Node` class encapsulates token spans, trivia attachments, and parent node references.

3. **Scope & Symbol Tracker (`src/analyzer/scope.sage`)**:
   - Builds hierarchical lexical scope trees (Global, Function, Block, Catch).
   - Tracks identifier declarations (`var`, `let`, `const`, `function`, parameters).
   - Differentiates authentic global references to `require`, `module`, and `exports` from shadowed local variables.
   - Traces variable alias chains (e.g., `const m = module.exports; m.field = ...`).

4. **Package & Path Resolver (`src/resolver/`)**:
   - Traverses directories and searches `node_modules` without calling external tools.
   - Parses `package.json` files using a native SageLang JSON parser.
   - Evaluates conditional `exports` maps (e.g., resolving the `"import"` condition over `"require"`).
   - Resolves extensionless relative paths and directory entries (`index.js`).

5. **Code Printer & Source Mapper (`src/printer/`)**:
   - Emits formatted JavaScript from transformed AST nodes.
   - Retains original formatting and indentation for untouched code segments.
   - Encodes source positions into standard Base64 VLQ source maps (`.js.map`).

---

## 2. Compatibility Baseline & Target Matrix

### 2.1 Target Runtime Matrix

Module features and APIs vary across Node.js LTS and modern releases. The transpiler supports configurable runtime targets via `--target`:

| Feature / API | `--target=node18` / `--target=node20` | `--target=node22` / `--target=node24+` |
|---|---|---|
| `__filename` / `__dirname` | `fileURLToPath(import.meta.url)` shim | `import.meta.filename`, `import.meta.dirname` |
| Entry Point Detection (`require.main === module`) | `process.argv[1] === fileURLToPath(import.meta.url)` | `import.meta.main` |
| JSON Import Syntax | `import data from "./f.json" with { type: "json" }` | `import data from "./f.json" with { type: "json" }` |
| Path Resolution API | `pathToFileURL` / `import.meta.url` | `import.meta.resolve()` |

### 2.2 Discord.js v14+ Compatibility Surface

Discord.js bots exercise complex CommonJS idioms. The transpiler explicitly validates against the following package surface:

* **Gateway & Core**: `Client`, `GatewayIntentBits`, `Partials`, `Events`.
* **Builders**: `SlashCommandBuilder`, `ContextMenuCommandBuilder`, `EmbedBuilder`, `ActionRowBuilder`, `ButtonBuilder`, `StringSelectMenuBuilder`.
* **REST & Routes**: `REST`, `Routes`, `discord-api-types/v10`.
* **Collections & Bitfields**: `Collection`, `PermissionsBitField`, `AttachmentBuilder`.
* **Sub-ecosystem**: `@discordjs/rest`, `@discordjs/ws`, `@discordjs/voice`, `@discordjs/builders`.
* **Dynamic Loaders**: Command and event registration loops scanning directories at startup.

---

## 3. Critical Edge Cases & Transformation Strategies

### 3.1 Import Hoisting vs. Inline Execution Order

**Issue:**
CommonJS executes `require()` synchronously in place. ESM `import` statements are statically hoisted and evaluated before any top-level module statements execute.

```js
// Original CJS
console.log("Initializing environment...");
require("dotenv").config();
const { Client } = require("discord.js");
```

Naively hoisting the `require` calls into imports results in `discord.js` evaluating *before* `dotenv.config()` populates `process.env`.

**Transpiler Strategy:**
1. The analyzer inspects whether any executable statements (function invocations, expressions, assignments) precede a `require()` call.
2. If side-effect ordering is detected:
   - **`--mode=strict`**: Fails closed with diagnostic `CJS201` when a require is dynamic, cache-dependent, non-leading, or requires a CommonJS runtime/export shim.
   - **`--mode=compat` (default)**: Retains inline execution order using `createRequire`:
     ```js
     import { createRequire } from "node:module";
     const require = createRequire(import.meta.url);

     console.log("Initializing environment...");
     require("dotenv").config();
     const { Client } = require("discord.js");
     ```

---

### 3.2 JSON Modules & Destructuring Synthesis

**Issue:**
In CommonJS, requiring JSON files allows direct destructuring:
```js
const { token, clientId } = require("./config.json");
```
Under modern ESM standards, JSON modules expose only a `default` export. Emitting `import { token, clientId } from "./config.json"` throws a runtime `SyntaxError`.

**Transpiler Strategy:**
The JSON transform pass detects JSON targets and synthesizes a default import accompanied by a local destructuring declaration:
```js
import config from "./config.json" with { type: "json" };
const { token, clientId } = config;
```

---

### 3.3 Dynamic `require()` & Module Cache Invalidation

**Issue:**
Discord bot command loaders frequently clear the CommonJS cache to implement hot reloading:
```js
delete require.cache[require.resolve(`./commands/${file}`)];
const command = require(`./commands/${file}`);
```
ESM's native dynamic `import()` caches modules in an immutable host map; Node.js provides no standard API to evict or reload modules via `import()`.

**Transpiler Strategy:**
1. The analyzer searches for property access or deletion on `require.cache`.
2. When cache clearing is detected, the transpiler **never** converts the dynamic require to `await import()`.
3. It emits `createRequire(import.meta.url)` to preserve cache manipulation behavior:
   ```js
   import { createRequire } from "node:module";
   const require = createRequire(import.meta.url);

   delete require.cache[require.resolve(`./commands/${file}`)];
   const command = require(`./commands/${file}`);
   ```
4. A diagnostic (`CJS202`) is emitted explaining that native ESM lacks module eviction.

---

### 3.4 Aliased & Mutated `module.exports`

**Issue:**
Older modules and utility packages often alias the export object or combine default and named exports unpredictably:
```js
const exp = module.exports;
exp.run = function() {};
exports.version = "1.0.0";
```
Or overwrite exports after property assignment:
```js
exports.foo = "bar";
module.exports = function main() {};
```

**Transpiler Strategy:**
1. The Scope Analyzer tracks references bound to `module.exports` and `exports`.
2. If `module.exports` is reassigned wholesale, previous property assignments are discarded to preserve CommonJS evaluation semantics.
3. For aliased property assignments, a composite export object is synthesized:
   ```js
   const exportsObject = {};
   const exp = exportsObject;
   exp.run = function() {};
   exportsObject.version = "1.0.0";

   export default exportsObject;
   export const run = exportsObject.run;
   export const version = exportsObject.version;
   ```

---

### 3.5 Runtime Globals & Entry-Point Detection

**Issue:**
`require.main === module` is commonly used in CLI tools and bot runners to execute logic only when a file is the direct entry point.

**Transpiler Strategy:**
Transform based on the specified `--target`:
* **Modern (`--target=node22+`)**:
  ```js
  if (import.meta.main) {
    main();
  }
  ```
* **Fallback (`--target=node18` / `--target=node20`)**:
  ```js
  import { fileURLToPath } from "node:url";
  import process from "node:process";

  if (process.argv[1] === fileURLToPath(import.meta.url)) {
    main();
  }
  ```

For `__dirname` and `__filename`:
* Target `node22+`: Emits `import.meta.dirname` and `import.meta.filename`.
* Target `node18/node20`:
  ```js
  import { fileURLToPath } from "node:url";
  import { dirname } from "node:path";

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  ```

---

### 3.6 Explicit Path & Extension Resolution

**Issue:**
CommonJS allows extensionless imports (`require("./utils")`) and directory imports (`require("./commands")`). ESM in Node.js mandates explicit file extensions and targets.

**Transpiler Strategy:**
The native SageLang path resolver inspects the physical directory structure during conversion:
* `./commands/ping` $\rightarrow$ `./commands/ping.js`
* `./utils` (directory with `index.js`) $\rightarrow$ `./utils/index.js`
* `./config` (resolving to `config.json`) $\rightarrow$ `./config.json` (plus import attributes)
* External packages (`discord.js`, `dotenv`) are preserved without extensions.

---

## 4. Discord.js Transformation Cases

### 4.1 Client Bootstrap

**CommonJS Source:**
```js
const { Client, GatewayIntentBits, Events } = require("discord.js");

const client = new Client({
  intents: [GatewayIntentBits.Guilds],
});

client.once(Events.ClientReady, c => {
  console.log(`Ready as ${c.user.tag}`);
});

client.login(process.env.DISCORD_TOKEN);
```

**Transformed ESM Output:**
```js
import { Client, GatewayIntentBits, Events } from "discord.js";

const client = new Client({
  intents: [GatewayIntentBits.Guilds],
});

client.once(Events.ClientReady, c => {
  console.log(`Ready as ${c.user.tag}`);
});

client.login(process.env.DISCORD_TOKEN);
```

---

### 4.2 Slash Command Builder

**CommonJS Source:**
```js
const { SlashCommandBuilder } = require("discord.js");

module.exports = {
  data: new SlashCommandBuilder()
    .setName("ping")
    .setDescription("Replies with Pong!"),
  async execute(interaction) {
    await interaction.reply("Pong!");
  },
};
```

**Transformed ESM Output:**
```js
import { SlashCommandBuilder } from "discord.js";

export default {
  data: new SlashCommandBuilder()
    .setName("ping")
    .setDescription("Replies with Pong!"),
  async execute(interaction) {
    await interaction.reply("Pong!");
  },
};
```

---

### 4.3 Filesystem Command Discovery Loader

**CommonJS Source:**
```js
const fs = require("node:fs");
const path = require("node:path");
const { Collection } = require("discord.js");

client.commands = new Collection();
const commandsPath = path.join(__dirname, "commands");
const commandFiles = fs.readdirSync(commandsPath).filter(f => f.endsWith(".js"));

for (const file of commandFiles) {
  const filePath = path.join(commandsPath, file);
  const command = require(filePath);
  if ("data" in command && "execute" in command) {
    client.commands.set(command.data.name, command);
  }
}
```

**Mode A: Compatibility Strategy (Default)**
```js
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { Collection } from "discord.js";

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

client.commands = new Collection();
const commandsPath = path.join(__dirname, "commands");
const commandFiles = fs.readdirSync(commandsPath).filter(f => f.endsWith(".js"));

for (const file of commandFiles) {
  const filePath = path.join(commandsPath, file);
  const command = require(filePath);
  if ("data" in command && "execute" in command) {
    client.commands.set(command.data.name, command);
  }
}
```

**Mode B: Async ESM Rewrite (`--rewrite-dynamic-imports`)**
```js
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { Collection } from "discord.js";

client.commands = new Collection();
const commandsPath = path.join(import.meta.dirname, "commands");
const commandFiles = fs.readdirSync(commandsPath).filter(f => f.endsWith(".js"));

for (const file of commandFiles) {
  const filePath = path.join(commandsPath, file);
  const commandModule = await import(pathToFileURL(filePath).href);
  const command = commandModule.default ?? commandModule;
  if ("data" in command && "execute" in command) {
    client.commands.set(command.data.name, command);
  }
}
```

---

## 5. SageLang Repository Structure

```text
cjs2esm/
├── Makefile / build.sage         # SageLang build and LLVM compilation script
├── README.md
├── plan.md                       # This specification document
│
├── src/
│   ├── main.sage                 # CLI Entry point, command routing, exit codes
│   │
│   ├── lexer/
│   │   ├── token.sage            # Token definitions, spans, TokenType enums
│   │   ├── scanner.sage          # Lexical scanner engine with streaming buffer
│   │   └── asi.sage              # Automatic Semicolon Insertion logic
│   │
│   ├── ast/
│   │   ├── nodes.sage            # Base AST Node, Expression, Statement classes
│   │   ├── declarations.sage     # Import, Export, Variable, Function AST nodes
│   │   └── visitor.sage          # AST Visitor and Node Mutator interfaces
│   │
│   ├── parser/
│   │   ├── parser.sage           # Recursive descent parsing coordinator
│   │   ├── expression.sage       # Pratt precedence expression parser
│   │   └── statements.sage       # Statement, block, and declaration parser
│   │
│   ├── analyzer/
│   │   ├── scope.sage            # Lexical Scope Tree & Identifier bindings
│   │   ├── classifier.sage       # Module classifier (PURE_CJS, DYNAMIC, etc.)
│   │   └── cjs_usage.sage        # Detects requires, exports, globals, and hoisting
│   │
│   ├── resolver/
│   │   ├── path_resolver.sage    # Relative path, extension, and directory index resolution
│   │   ├── package_json.sage     # Conditional exports & package resolution
│   │   └── node_builtins.sage    # Built-in modules list (node:fs, path, etc.)
│   │
│   ├── transform/
│   │   ├── context.sage          # Transform pass state and active configuration
│   │   ├── pass_imports.sage     # Static/destructured require to import
│   │   ├── pass_exports.sage     # module.exports / exports.* to export declarations
│   │   ├── pass_globals.sage     # __dirname, __filename, require.resolve, require.main
│   │   ├── pass_dynamic.sage     # createRequire injection or async dynamic import shims
│   │   └── pass_json.sage        # JSON import attributes and destructuring synthesis
│   │
│   ├── printer/
│   │   ├── codegen.sage          # Formatted JavaScript source code emitter
│   │   ├── sourcemap.sage        # Base64 VLQ source map generator (.map)
│   │   └── comments.sage         # Trivia attachment and comment preservation
│   │
│   └── project/
│       ├── workspace.sage        # Multi-file graph orchestrator and file I/O
│       ├── manifest.sage         # package.json updates ("type": "module")
│       └── reporter.sage         # JSON/Markdown migration report generator
│
└── tests/
    ├── runner.sage               # Native SageLang integration test runner
    ├── fixtures/
    │   ├── basic/                # Primitives, functions, control flow
    │   ├── exports/              # Object exports, aliasing, reassignments
    │   ├── json/                 # JSON attribute imports and destructuring
    │   └── discordjs/            # Headless Discord.js mock test suites
    │       ├── bot-bootstrap/
    │       ├── command-handler/
    │       ├── event-handler/
    │       └── slash-builders/
```

---

## 6. Confidence Engine & Diagnostic Codes

Every transformed construct is evaluated against confidence levels:

* `[SAFE]`: Mechanically exact conversion (e.g., static named require).
* `[LIKELY_SAFE]`: Extension or directory resolution backed by filesystem lookup.
* `[COMPAT_SHIM]`: Preserved via `createRequire` or URL shim.
* `[SEMANTIC_CHANGE]`: Asynchronous or order-dependent transformation.
* `[MANUAL_REVIEW]`: Dynamic runtime mutation of exports that cannot be safely determined.

### Diagnostic Registry

* `CJS101` — **Destructured require converted to named ESM import** (`[SAFE]`).
* `CJS102` — **Dynamic require preserved via `createRequire`** (`[COMPAT_SHIM]`).
* `CJS103` — **`__dirname` / `__filename` converted to target specifier** (`[SAFE]`).
* `CJS104` — **JSON require rewritten with import attributes & synthesized bindings** (`[SAFE]`).
* `CJS201` — **Strict-mode safety rejection for dynamic, order-sensitive, or shim-dependent constructs** (`[ERROR]`).
* `CJS202` — **`require.cache` access detected: module unloading or cache inspection remains on `createRequire`** (`[MANUAL_REVIEW]`).
* `CJS301` — **Dynamic export structure preserved via default export object** (`[COMPAT_SHIM]`).
* `CJS405` — **Output relocation would change relative `require()` resolution** (`[ERROR]`).

---

## 7. CLI Specification

The compiled SageLang binary provides the following command-line interface:

```bash
cjs2esm convert <input-path> [options]
cjs2esm inspect <file-path>
cjs2esm check <project-path>
cjs2esm report <project-path>
```

### Options & Flags

* `--out=<dir>`: Output directory for transpiled files (defaults to in-place or `./dist`). Files containing `require()` are rejected when moved to a different directory until output-path rebasing is implemented.
* `--target=<node18|node20|node22|node24>`: Target Node.js baseline (default: `node20`).
* `--mode=<strict|compat|discord>`:
  - `strict`: Accept only leading static imports; reject dynamic, order-sensitive, cache-dependent, and shim-dependent constructs.
  - `compat`: Automatically inject `createRequire` and fallback shims where needed.
  - `discord`: Optimized for Discord.js bot architectures; handles dynamic command loaders.
* `--rewrite-dynamic-imports`: Converts filesystem dynamic `require()` calls into `await import()`.
* `--source-maps`: Generates `.map` files alongside converted `.js` files.
* `--update-package-json`: Updates or injects `"type": "module"` in `package.json`.
* `--dry-run`: Runs analysis, prints diagnostics, and generates report without writing to disk.

---

## 8. Verification & Differential Testing Strategy

### 8.1 Headless Discord.js Fixture Suite

To ensure deterministic CI runs without network dependencies or live gateway tokens, testing is conducted offline:

1. **Builder Serialization Verification**:
   - Construct `SlashCommandBuilder` and `EmbedBuilder` instances in CJS.
   - Convert the fixtures to ESM using `cjs2esm`.
   - Run both in Node.js and assert that `.toJSON()` serialized outputs match byte-for-byte.

2. **Routes & REST Formatters**:
   - Compare strings generated by `Routes.applicationCommands(clientId)` and permissions bitfield calculations between CJS and generated ESM.

3. **Collection Behavior**:
   - Confirm that instances of `Collection` instantiated within converted event/command loaders preserve custom utility methods (`filter`, `map`, `first`).

4. **Circular Reference Graphs**:
   - Stress-test circular dependency chains (e.g., `Client` references `Command`, `Command` references `Client`) to verify that ESM live bindings resolve without temporal dead zone (`ReferenceError`) failures.

---

## 9. Security & Secret Redaction

Bot repositories frequently store tokens and keys in local configuration files or scripts. The transpiler guarantees:

* **Token Redaction**: Any token matching regex patterns for Discord Bot tokens (`[MNO][A-Za-z\d]{23,}\.[\w-]{6}\.[\w-]{27,}`) is stripped from diagnostic outputs and reports.
* **Non-Execution**: The transpiler parses ASTs statically and never evaluates or executes project source code at transform time.
* **Credential Isolation**: Planned. `.env` and secret configuration files are not yet specially excluded from diagnostic output.

---

## 10. Phased Implementation Roadmap

### Phase 1: Lexer, Parser & AST Foundation (in SageLang)
- [x] Implement a byte-accurate JavaScript scanner with template, regex, comment, and ASI token handling.
- [x] Implement Pratt expression parsing and top-level statement splitting in SageLang.
- [x] Add foundational AST declaration nodes and visitor interfaces.
- [ ] Complete ESTree-compatible AST construction and mutation.

### Phase 2: Scope Analysis & CommonJS Classifier
- [ ] Implement lexical scope stack tracking `var`, `let`, `const`, `function`, and parameters.
- [ ] Build identifier binding resolver to identify shadowed `require`/`module`/`exports`.
- [ ] Implement `cjs_usage.sage` to tag module classifications (`PURE_CJS`, `DYNAMIC_EXPORTS`, etc.).

### Phase 3: Core Import & Export Transformations
- [x] Implement leading static require conversion (`const x = require("x")`, destructured, property access).
- [ ] Complete semantic export passes (`module.exports = ...`, `exports.key = ...`, object literals, aliases, and wholesale reassignment).
- [x] Implement JSON module handling (default import + import attributes + destructuring synthesis).
- [x] Implement conservative Node runtime global replacements (`__dirname`, `__filename`, `require.main`).

### Phase 4: Dynamic Requires, Shims & Hoisting Guards
- [x] Detect statement-preceded requires and preserve order with `createRequire`; strict mode fails with `CJS201`.
- [x] Implement dynamic require fallback using `createRequire(import.meta.url)`.
- [x] Implement conservative entry-point detection (`require.main === module`).
- [x] Implement relative path resolution for extensions, `package.json` main fields, and directory indexes.
- [ ] Add complete flow-aware hoisting and export analysis.

### Phase 5: Code Generator & Source Map Emitter
- [ ] Implement `codegen.sage` formatting output AST back to JavaScript.
- [x] Implement Base64 VLQ source map encoder generating `.map` files.
- [x] Preserve untouched source text and line-level mappings.

### Phase 6: Project Orchestrator & CLI
- [x] Implement CLI argument parsing and recursive filesystem workspace traversal in SageLang.
- [x] Implement `package.json` updater (`"type": "module"`).
- [x] Implement diagnostic engine with secret redaction.
- [x] Implement Markdown migration summary reports (`cjs2esm-report.md`).

### Phase 7: Discord.js Integration & Differential Testing
- [x] Run Node differential checks for dependency-free CJS/ESM runtime fixtures.
- [ ] Add Discord.js mock packages for `SlashCommandBuilder`, `EmbedBuilder`, `Routes`, and event handlers.
- [ ] Run end-to-end migration on a full, multi-command real-world CommonJS Discord bot.
