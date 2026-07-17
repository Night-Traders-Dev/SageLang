#!/bin/bash

clear
echo "Native Sage -O3"
./bench
echo "Sage AOT"
./bench_aot
echo "Sage JIT"
./bench_jit
echo "Sage AOT + JIT"
./bench_aot_jit
