# SageLang Test Suite

All tests live here. One runner to rule them all.

## Quick Start

```sh
# Build first (from repo root or core/)
make

# Run everything
sh testsuite/run_all.sh

# Run specific suite
sh testsuite/run_all.sh unit        # numbered language unit tests
sh testsuite/run_all.sh compiler    # C/LLVM backend compiler tests
sh testsuite/run_all.sh selfhost    # self-hosted Sage-in-Sage tests
sh testsuite/run_all.sh benchmarks  # perf benchmarks
sh testsuite/run_all.sh quick       # unit + compiler only (fast)
```

## Structure

```
testsuite/
├── run_all.sh          ← MEGA runner — runs all suites, prints summary
│
├── unit/               ← 43 numbered language test suites (01_variables … 43_blockchain)
│   ├── 01_variables/   ← each subdir has .sage files + .expected output
│   ├── 02_arithmetic/
│   ├── ...
│   ├── 43_blockchain/
│   └── run_tests.sh    ← original suite runner (called by run_all.sh)
│
├── compiler/           ← C backend + LLVM backend tests
│   ├── compiler_smoke.sage / .expected
│   ├── compiler_arrays.sage / .expected
│   ├── ...             ← paired .sage + .expected for each feature
│   ├── llvm_features.sage / .expected
│   ├── test.sage       ← interpreter smoke test
│   └── lib_suite.sage  ← stdlib smoke test
│
├── selfhost/           ← self-hosted interpreter tests (Sage interpreting Sage)
│   ├── test_lexer.sage
│   ├── test_parser.sage
│   ├── test_interpreter.sage
│   └── ...             ← run from within core/src/sage/ for import resolution
│
├── benchmarks/         ← performance benchmarks
│   ├── 01_fibonacci.sage / .py
│   ├── 02_loop_sum.sage / .py
│   ├── ...
│   ├── backend_compare.sage
│   └── run_backend_compare.sh
│
└── misc/               ← root-level test scripts (networking, discord, etc.)
    ├── test_client.sage
    ├── test_discord.sage
    └── ...
```

## Notes

- **selfhost tests** run `cd core/src/sage && sage ../../testsuite/selfhost/test_X.sage`
  — the working directory makes `import lexer` etc. resolve correctly.
- **compiler tests** need the sage binary built at `core/sage`.
- `run_all.sh` auto-builds if the binary is missing.
- Benchmarks need `python3` for the comparison script; otherwise individual `.sage` files run solo.
