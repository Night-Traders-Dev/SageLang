#!/bin/bash
## Run script for SageLang Minimal OS PoC (SageVM Pipeline)
cd "$(dirname "$0")"

SGVM=../core/sgvm
KERNEL_SGVM=kernel.sgvm

echo "Booting Minimal OS (SageVM Pipeline)..."
$SGVM $KERNEL_SGVM
