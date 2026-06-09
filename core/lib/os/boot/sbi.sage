## os.boot.sbi — RISC-V SBI Interface
## Provides wrappers for RISC-V Supervisor Binary Interface (SBI) calls.

## Get SBI specification version
proc get_spec_version():
    # ecall logic
    return 0
end

## Print a character via SBI
proc console_putchar(c):
    # ecall FID=1
    return nil
end

## Start a secondary heart
proc hart_start(hartid, start_addr, opaque):
    return 0
end

## Reset the system via SBI
proc system_reset(reset_type):
    return nil
end
