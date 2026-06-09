#!/bin/bash

## Build script for SageLang Minimal OS PoC (SageVM Pipeline)
## Ensure we are in the script's directory
cd "$(dirname "$0")"

SGVMC=/home/elf_g/testOS/src/sgvmc
KERNEL_SAGE=kernel.sage
KERNEL_SGVM=kernel.sgvm

echo "Compiling Minimal OS (SageVM Pipeline)..."

## Compile the kernel to bytecode
echo "Compiling kernel to bytecode..."
$SGVMC $KERNEL_SAGE $KERNEL_SGVM

echo "Kernel built: $KERNEL_SGVM"
