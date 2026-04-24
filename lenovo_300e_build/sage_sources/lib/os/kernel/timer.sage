gc_disable()

# timer.sage — Programmable Interval Timer (PIT) driver
# Configures PIT channel 0 for periodic interrupts.

# ----- PIT constants -----
let PIT_FREQ = 1193182
let PIT_CHANNEL0 = 64
let PIT_CMD = 67

# ----- Timer state -----
let tick_count = 0
let timer_freq = 0
let ms_per_tick = 0
let timer_handler = nil
let timer_ready = false

proc init(frequency_hz):
    if frequency_hz < 1:
        frequency_hz = 1
    end
    timer_freq = frequency_hz
    # Calculate the PIT divisor
    let divisor = PIT_FREQ / frequency_hz

    # In a real kernel we would:
    #   outb(PIT_CMD, 0x36)        — channel 0, lo/hi, rate generator
    #   outb(PIT_CHANNEL0, divisor & 0xFF)
    #   outb(PIT_CHANNEL0, (divisor >> 8) & 0xFF)

    ms_per_tick = 1000 / frequency_hz
    tick_count = 0
    timer_handler = nil
    timer_ready = true
end

proc tick():
    # Called by the IRQ0 handler on each timer interrupt.
    tick_count = tick_count + 1
    if timer_handler != nil:
        timer_handler()
    end
end

proc get_ticks():
    return tick_count
end

proc get_uptime_ms():
    return tick_count * ms_per_tick
end

proc get_uptime_s():
    return get_uptime_ms() / 1000
end

proc sleep_ms(ms):
    if timer_ready == false:
        return
    end
    let target = get_uptime_ms() + ms
    while get_uptime_ms() < target:
        # busy-wait
        let dummy = 0
    end
end

proc sleep_s(s):
    sleep_ms(s * 1000)
end

proc set_handler(callback):
    timer_handler = callback
end

proc get_frequency():
    return timer_freq
end

proc reset():
    tick_count = 0
end

proc stats():
    let s = {}
    s["ticks"] = tick_count
    s["frequency_hz"] = timer_freq
    s["ms_per_tick"] = ms_per_tick
    s["uptime_ms"] = get_uptime_ms()
    s["uptime_s"] = get_uptime_s()
    return s
end

# ================================================================
# aarch64 Generic Timer support
# ================================================================
# The ARM Generic Timer uses system registers:
#   CNTFRQ_EL0  — counter frequency (set by firmware)
#   CNTP_TVAL_EL0 — timer value (countdown)
#   CNTP_CTL_EL0  — control (bit 0 = ENABLE, bit 1 = IMASK)

proc aarch64_timer_config(freq_hz):
    let cfg = {}
    # CNTFRQ is typically set by firmware (e.g., 62.5 MHz on many boards)
    # but we store the desired interrupt frequency
    cfg["arch"] = "aarch64"
    cfg["freq_hz"] = freq_hz
    cfg["cntfrq"] = 62500000
    # Timer value: number of counter ticks between interrupts
    cfg["cntp_tval"] = cfg["cntfrq"] / freq_hz
    # Control: ENABLE=1, IMASK=0
    cfg["cntp_ctl"] = 1
    return cfg
end

proc aarch64_timer_init_sequence(freq_hz):
    let cfg = aarch64_timer_config(freq_hz)
    let seq = []
    # Step 1: Write CNTP_TVAL_EL0 (countdown value)
    let s1 = {}
    s1["reg"] = "CNTP_TVAL_EL0"
    s1["value"] = cfg["cntp_tval"]
    push(seq, s1)
    # Step 2: Write CNTP_CTL_EL0 (enable timer, unmask interrupt)
    let s2 = {}
    s2["reg"] = "CNTP_CTL_EL0"
    s2["value"] = cfg["cntp_ctl"]
    push(seq, s2)
    return seq
end

# ================================================================
# riscv64 CLINT timer support
# ================================================================
# CLINT memory-mapped registers:
#   MTIME    — 64-bit free-running counter (at clint_base + 0xBFF8)
#   MTIMECMP — 64-bit compare register (at clint_base + 0x4000, per-hart)

proc riscv64_timer_config(clint_base, freq_hz):
    let cfg = {}
    cfg["arch"] = "riscv64"
    cfg["clint_base"] = clint_base
    cfg["freq_hz"] = freq_hz
    cfg["mtime_addr"] = clint_base + 49144
    cfg["mtimecmp_addr"] = clint_base + 16384
    # Assume 10 MHz default timer frequency (common in QEMU/SiFive)
    cfg["timer_freq"] = 10000000
    cfg["interval"] = cfg["timer_freq"] / freq_hz
    return cfg
end

proc riscv64_timer_init_sequence(clint_base, freq_hz):
    let cfg = riscv64_timer_config(clint_base, freq_hz)
    let seq = []
    # Step 1: Read MTIME to get current counter
    let s1 = {}
    s1["addr"] = cfg["mtime_addr"]
    s1["action"] = "read64"
    s1["label"] = "current_time"
    push(seq, s1)
    # Step 2: Write MTIMECMP = current_time + interval
    let s2 = {}
    s2["addr"] = cfg["mtimecmp_addr"]
    s2["value"] = cfg["interval"]
    s2["action"] = "write64_add_current"
    push(seq, s2)
    return seq
end

# ================================================================
# Multi-architecture timer dispatcher
# ================================================================

proc timer_init(arch, config):
    if arch == "x86" or arch == "x86_64":
        let freq = 100
        if config != nil:
            if config["freq_hz"] != nil:
                freq = config["freq_hz"]
            end
        end
        init(freq)
        return stats()
    end
    if arch == "aarch64":
        let freq = 100
        if config != nil:
            if config["freq_hz"] != nil:
                freq = config["freq_hz"]
            end
        end
        let result = {}
        result["arch"] = "aarch64"
        result["config"] = aarch64_timer_config(freq)
        result["init_sequence"] = aarch64_timer_init_sequence(freq)
        return result
    end
    if arch == "riscv64":
        let clint_base = 33554432
        let freq = 100
        if config != nil:
            if config["clint_base"] != nil:
                clint_base = config["clint_base"]
            end
            if config["freq_hz"] != nil:
                freq = config["freq_hz"]
            end
        end
        let result = {}
        result["arch"] = "riscv64"
        result["config"] = riscv64_timer_config(clint_base, freq)
        result["init_sequence"] = riscv64_timer_init_sequence(clint_base, freq)
        return result
    end
    return nil
end

# ================================================================
# Hardware I/O Assembly Emission
# ================================================================

comptime:
    let PIT_BASE_FREQ = 1193182
    let PIT_CHANNEL0_PORT = 64
    let PIT_CMD_PORT = 67
    let PIT_MODE3_CMD = 54
    let PIC_CMD_PORT = 32
    let EOI_BYTE = 32
    let CLINT_MTIMECMP_OFFSET = 16384
    let CLINT_MTIME_OFFSET = 49144
end

proc emit_pit_init_asm(frequency):
    # x86_64 assembly to initialize PIT channel 0
    let nl = chr(10)
    let tab = chr(9)
    let divisor = 1193182 / frequency
    let divisor_lo = divisor % 256
    let divisor_hi = (divisor / 256) % 256
    let asm = ""
    asm = asm + ".global pit_init" + nl
    asm = asm + ".type pit_init, @function" + nl
    asm = asm + "pit_init:" + nl
    # Command byte: channel 0, lo/hi byte, mode 3 (square wave)
    asm = asm + tab + "movb $0x36, %al" + nl
    asm = asm + tab + "outb %al, $0x43" + nl
    # Send low byte of divisor to channel 0 data port
    asm = asm + tab + "movb $" + str(divisor_lo) + ", %al" + nl
    asm = asm + tab + "outb %al, $0x40" + nl
    # Send high byte of divisor to channel 0 data port
    asm = asm + tab + "movb $" + str(divisor_hi) + ", %al" + nl
    asm = asm + tab + "outb %al, $0x40" + nl
    asm = asm + tab + "ret" + nl
    return asm
end

proc emit_timer_isr_asm():
    # x86_64 assembly for IRQ0 (timer) interrupt handler
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global timer_isr" + nl
    asm = asm + ".type timer_isr, @function" + nl
    asm = asm + "timer_isr:" + nl
    # Save rax
    asm = asm + tab + "push %rax" + nl
    # Increment global tick_count
    asm = asm + tab + "movq tick_count_hw(%rip), %rax" + nl
    asm = asm + tab + "incq %rax" + nl
    asm = asm + tab + "movq %rax, tick_count_hw(%rip)" + nl
    # Send EOI to PIC
    asm = asm + tab + "movb $0x20, %al" + nl
    asm = asm + tab + "outb %al, $0x20" + nl
    # Restore rax
    asm = asm + tab + "pop %rax" + nl
    asm = asm + tab + "iretq" + nl
    asm = asm + nl
    # Global tick counter variable
    asm = asm + ".section .bss" + nl
    asm = asm + ".global tick_count_hw" + nl
    asm = asm + "tick_count_hw:" + nl
    asm = asm + tab + ".quad 0" + nl
    return asm
end

proc emit_aarch64_timer_init_asm(freq):
    # aarch64 assembly to initialize the Generic Timer
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global aarch64_timer_init_hw" + nl
    asm = asm + ".type aarch64_timer_init_hw, @function" + nl
    asm = asm + "aarch64_timer_init_hw:" + nl
    # Load interval value into x0
    asm = asm + tab + "mov x0, #" + str(freq) + nl
    # Set CNTV_TVAL_EL0 (virtual timer value)
    asm = asm + tab + "msr CNTV_TVAL_EL0, x0" + nl
    # Enable virtual timer: set bit 0 of CNTV_CTL_EL0
    asm = asm + tab + "mov x0, #1" + nl
    asm = asm + tab + "msr CNTV_CTL_EL0, x0" + nl
    asm = asm + tab + "ret" + nl
    return asm
end

proc emit_riscv64_timer_init_asm(interval):
    # riscv64 assembly to initialize CLINT timer (QEMU virt platform)
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global riscv64_timer_init_hw" + nl
    asm = asm + ".type riscv64_timer_init_hw, @function" + nl
    asm = asm + "riscv64_timer_init_hw:" + nl
    # Load CLINT base address (0x02000000 for QEMU virt)
    asm = asm + tab + "li t0, 0x02000000" + nl
    # Load MTIME: base + 0xBFF8
    asm = asm + tab + "li t1, 0xBFF8" + nl
    asm = asm + tab + "add t1, t0, t1" + nl
    asm = asm + tab + "ld t2, 0(t1)" + nl
    # Add interval to current MTIME
    asm = asm + tab + "li t3, " + str(interval) + nl
    asm = asm + tab + "add t2, t2, t3" + nl
    # Store to MTIMECMP: base + 0x4000
    asm = asm + tab + "li t1, 0x4000" + nl
    asm = asm + tab + "add t1, t0, t1" + nl
    asm = asm + tab + "sd t2, 0(t1)" + nl
    asm = asm + tab + "ret" + nl
    return asm
end
