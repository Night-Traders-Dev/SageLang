# x86-64 Interrupt Descriptor Table (IDT) helpers
# Provides IDT entry construction, exception vector constants,
# and descriptor building utilities for OS kernel development

# Gate type constants
let GATE_INTERRUPT = 14
let GATE_TRAP = 15
let GATE_TASK = 5

# DPL (Descriptor Privilege Level) constants
let DPL_KERNEL = 0
let DPL_USER = 3

# IST (Interrupt Stack Table) - 0 means no IST
let IST_NONE = 0
let IST_1 = 1
let IST_2 = 2
let IST_3 = 3
let IST_4 = 4
let IST_5 = 5
let IST_6 = 6
let IST_7 = 7

# x86 exception vectors
let DIVIDE_ERROR = 0
let DEBUG = 1
let NMI = 2
let BREAKPOINT = 3
let OVERFLOW = 4
let BOUND_RANGE = 5
let INVALID_OPCODE = 6
let DEVICE_NOT_AVAIL = 7
let DOUBLE_FAULT = 8
let COPROC_SEGMENT = 9
let INVALID_TSS = 10
let SEGMENT_NOT_PRESENT = 11
let STACK_FAULT = 12
let GENERAL_PROTECTION = 13
let PAGE_FAULT = 14
let X87_FP_ERROR = 16
let ALIGNMENT_CHECK = 17
let MACHINE_CHECK = 18
let SIMD_FP_ERROR = 19
let VIRTUALIZATION = 20
let CONTROL_PROTECTION = 21
let HYPERVISOR_INJECTION = 28
let VMM_COMMUNICATION = 29
let SECURITY_EXCEPTION = 30

# IRQ vectors (PIC remapped to 32-47)
let IRQ_BASE = 32
let IRQ_TIMER = 32
let IRQ_KEYBOARD = 33
let IRQ_CASCADE = 34
let IRQ_COM2 = 35
let IRQ_COM1 = 36
let IRQ_LPT2 = 37
let IRQ_FLOPPY = 38
let IRQ_LPT1 = 39
let IRQ_RTC = 40
let IRQ_FREE1 = 41
let IRQ_FREE2 = 42
let IRQ_FREE3 = 43
let IRQ_MOUSE = 44
let IRQ_FPU = 45
let IRQ_PRIMARY_ATA = 46
let IRQ_SECONDARY_ATA = 47

# APIC/IOAPIC vectors
let APIC_TIMER = 48
let APIC_ERROR = 49
let APIC_SPURIOUS = 255

# Syscall vector (common convention)
let SYSCALL_VECTOR = 128

proc exception_name(vec):
    if vec == 0:
        return "Divide Error"
    end
    if vec == 1:
        return "Debug"
    end
    if vec == 2:
        return "NMI"
    end
    if vec == 3:
        return "Breakpoint"
    end
    if vec == 4:
        return "Overflow"
    end
    if vec == 5:
        return "Bound Range"
    end
    if vec == 6:
        return "Invalid Opcode"
    end
    if vec == 7:
        return "Device Not Available"
    end
    if vec == 8:
        return "Double Fault"
    end
    if vec == 10:
        return "Invalid TSS"
    end
    if vec == 11:
        return "Segment Not Present"
    end
    if vec == 12:
        return "Stack Fault"
    end
    if vec == 13:
        return "General Protection"
    end
    if vec == 14:
        return "Page Fault"
    end
    if vec == 16:
        return "x87 FP Error"
    end
    if vec == 17:
        return "Alignment Check"
    end
    if vec == 18:
        return "Machine Check"
    end
    if vec == 19:
        return "SIMD FP Error"
    end
    if vec == 20:
        return "Virtualization"
    end
    if vec == 21:
        return "Control Protection"
    end
    return "Unknown"
end

# Returns true if the exception pushes an error code
proc has_error_code(vec):
    if vec == 8:
        return true
    end
    if vec == 10:
        return true
    end
    if vec == 11:
        return true
    end
    if vec == 12:
        return true
    end
    if vec == 13:
        return true
    end
    if vec == 14:
        return true
    end
    if vec == 17:
        return true
    end
    if vec == 21:
        return true
    end
    if vec == 29:
        return true
    end
    if vec == 30:
        return true
    end
    return false
end

# Create an IDT gate descriptor (returns dict with raw field values)
# handler_addr: 64-bit address of the ISR
# selector: code segment selector (typically 0x08 for kernel CS)
# ist: IST index (0-7, 0 = no IST)
# gate_type: GATE_INTERRUPT (14) or GATE_TRAP (15)
# dpl: privilege level (0 = kernel, 3 = user)
proc make_gate(handler_addr, selector, ist, gate_type, dpl):
    let gate = {}
    gate["handler"] = handler_addr
    gate["selector"] = selector
    gate["ist"] = ist & 7
    gate["gate_type"] = gate_type
    gate["dpl"] = dpl
    gate["present"] = true
    gate["type_name"] = "Unknown"
    if gate_type == 14:
        gate["type_name"] = "Interrupt"
    end
    if gate_type == 15:
        gate["type_name"] = "Trap"
    end

    # Build the 16 raw bytes of the IDT entry
    let offset_lo = handler_addr & 65535
    let offset_mid = (handler_addr >> 16) & 65535
    let offset_hi = (handler_addr >> 32) & 4294967295

    # Type/attr byte: P(1) DPL(2) 0(1) TYPE(4)
    let type_attr = 128 + ((dpl & 3) << 5) + (gate_type & 15)

    gate["offset_lo"] = offset_lo
    gate["offset_mid"] = offset_mid
    gate["offset_hi"] = offset_hi
    gate["type_attr"] = type_attr

    # Raw bytes (16 bytes per entry)
    let bytes = []
    # Bytes 0-1: offset low
    push(bytes, offset_lo & 255)
    push(bytes, (offset_lo >> 8) & 255)
    # Bytes 2-3: selector
    push(bytes, selector & 255)
    push(bytes, (selector >> 8) & 255)
    # Byte 4: IST
    push(bytes, ist & 7)
    # Byte 5: type_attr
    push(bytes, type_attr)
    # Bytes 6-7: offset mid
    push(bytes, offset_mid & 255)
    push(bytes, (offset_mid >> 8) & 255)
    # Bytes 8-11: offset high
    push(bytes, offset_hi & 255)
    push(bytes, (offset_hi >> 8) & 255)
    push(bytes, (offset_hi >> 16) & 255)
    push(bytes, (offset_hi >> 24) & 255)
    # Bytes 12-15: reserved (zero)
    push(bytes, 0)
    push(bytes, 0)
    push(bytes, 0)
    push(bytes, 0)
    gate["bytes"] = bytes
    return gate
end

# Convenience: create a kernel interrupt gate
proc interrupt_gate(handler_addr, selector):
    return make_gate(handler_addr, selector, 0, 14, 0)
end

# Convenience: create a kernel trap gate
proc trap_gate(handler_addr, selector):
    return make_gate(handler_addr, selector, 0, 15, 0)
end

# Convenience: create a user-callable interrupt gate (for syscalls)
proc user_interrupt_gate(handler_addr, selector):
    return make_gate(handler_addr, selector, 0, 14, 3)
end

# Convenience: create an interrupt gate with IST
proc ist_interrupt_gate(handler_addr, selector, ist):
    return make_gate(handler_addr, selector, ist, 14, 0)
end

# Create an IDT descriptor table (256 entries)
# handler_table: dict mapping vector number -> handler address
# selector: kernel code segment selector
proc build_idt(handler_table, selector):
    let idt = []
    for i in range(256):
        if dict_has(handler_table, i):
            let addr = handler_table[i]
            push(idt, interrupt_gate(addr, selector))
        else:
            # Not-present entry (all zeros)
            let empty = {}
            empty["handler"] = 0
            empty["present"] = false
            let bytes = []
            for j in range(16):
                push(bytes, 0)
            end
            empty["bytes"] = bytes
            push(idt, empty)
        end
    end
    return idt
end

# Flatten IDT to raw byte array (256 * 16 = 4096 bytes)
proc idt_to_bytes(idt):
    let bytes = []
    for i in range(len(idt)):
        let entry_bytes = idt[i]["bytes"]
        for j in range(16):
            push(bytes, entry_bytes[j])
        end
    end
    return bytes
end

# Build IDTR descriptor (6 bytes: 2 limit + 4/8 base)
proc make_idtr(base_addr):
    let idtr = {}
    idtr["limit"] = 256 * 16 - 1
    idtr["base"] = base_addr
    # Raw bytes (10 bytes for 64-bit: 2 limit + 8 base)
    let bytes = []
    let limit = 4095
    push(bytes, limit & 255)
    push(bytes, (limit >> 8) & 255)
    push(bytes, base_addr & 255)
    push(bytes, (base_addr >> 8) & 255)
    push(bytes, (base_addr >> 16) & 255)
    push(bytes, (base_addr >> 24) & 255)
    push(bytes, (base_addr >> 32) & 255)
    push(bytes, (base_addr >> 40) & 255)
    push(bytes, (base_addr >> 48) & 255)
    push(bytes, (base_addr >> 56) & 255)
    idtr["bytes"] = bytes
    return idtr
end

# Parse an IDT entry from 16 raw bytes
proc parse_gate(bs, off):
    let gate = {}
    let offset_lo = bs[off] + bs[off + 1] * 256
    let selector = bs[off + 2] + bs[off + 3] * 256
    let ist = bs[off + 4] & 7
    let type_attr = bs[off + 5]
    let offset_mid = bs[off + 6] + bs[off + 7] * 256
    let offset_hi = bs[off + 8] + bs[off + 9] * 256 + bs[off + 10] * 65536 + bs[off + 11] * 16777216
    gate["handler"] = offset_lo + offset_mid * 65536 + offset_hi * 4294967296
    gate["selector"] = selector
    gate["ist"] = ist
    gate["present"] = (type_attr & 128) != 0
    gate["dpl"] = (type_attr >> 5) & 3
    gate["gate_type"] = type_attr & 15
    if (type_attr & 15) == 14:
        gate["type_name"] = "Interrupt"
    end
    if (type_attr & 15) == 15:
        gate["type_name"] = "Trap"
    end
    if not dict_has(gate, "type_name"):
        gate["type_name"] = "Unknown"
    end
    return gate
end

# PIC (8259) initialization command words
let PIC1_CMD = 32
let PIC1_DATA = 33
let PIC2_CMD = 160
let PIC2_DATA = 161

# Generate PIC remapping sequence (remap IRQs to vector_base..vector_base+15)
proc pic_remap_sequence(vector_base):
    let seq = []
    # ICW1: init + ICW4 needed
    let s = {}
    s["port"] = 32
    s["value"] = 17
    push(seq, s)
    let s2 = {}
    s2["port"] = 160
    s2["value"] = 17
    push(seq, s2)
    # ICW2: vector offsets
    let s3 = {}
    s3["port"] = 33
    s3["value"] = vector_base
    push(seq, s3)
    let s4 = {}
    s4["port"] = 161
    s4["value"] = vector_base + 8
    push(seq, s4)
    # ICW3: cascade
    let s5 = {}
    s5["port"] = 33
    s5["value"] = 4
    push(seq, s5)
    let s6 = {}
    s6["port"] = 161
    s6["value"] = 2
    push(seq, s6)
    # ICW4: 8086 mode
    let s7 = {}
    s7["port"] = 33
    s7["value"] = 1
    push(seq, s7)
    let s8 = {}
    s8["port"] = 161
    s8["value"] = 1
    push(seq, s8)
    # Mask all IRQs initially
    let s9 = {}
    s9["port"] = 33
    s9["value"] = 255
    push(seq, s9)
    let s10 = {}
    s10["port"] = 161
    s10["value"] = 255
    push(seq, s10)
    return seq
end

# ============================================================================
# aarch64 GIC (Generic Interrupt Controller) support
# ============================================================================

# Default GIC base addresses (GICv2, platform-dependent)
let GICD_BASE = 0x08000000
let GICC_BASE = 0x08010000

# GIC Distributor register offsets
let GICD_CTLR       = 0x000
let GICD_TYPER      = 0x004
let GICD_IIDR       = 0x008
let GICD_IGROUPR    = 0x080
let GICD_ISENABLER  = 0x100
let GICD_ICENABLER  = 0x180
let GICD_ISPENDR    = 0x200
let GICD_ICPENDR    = 0x280
let GICD_ISACTIVER  = 0x300
let GICD_ICACTIVER  = 0x380
let GICD_IPRIORITYR = 0x400
let GICD_ITARGETSR  = 0x800
let GICD_ICFGR      = 0xC00

# GIC CPU Interface register offsets
let GICC_CTLR  = 0x000
let GICC_PMR   = 0x004
let GICC_BPR   = 0x008
let GICC_IAR   = 0x00C
let GICC_EOIR  = 0x010
let GICC_RPR   = 0x014
let GICC_HPPIR = 0x018

# GIC interrupt type constants
let GIC_SPI_START = 32
let GIC_PPI_START = 16
let GIC_SGI_START = 0
let GIC_MAX_IRQS  = 1020

# Returns a dict describing the GIC Distributor register layout
# base_addr: physical base address of the GICD
proc gic_dist_config(base_addr):
    let cfg = {}
    cfg["base"] = base_addr
    cfg["ctlr"] = base_addr + GICD_CTLR
    cfg["typer"] = base_addr + GICD_TYPER
    cfg["iidr"] = base_addr + GICD_IIDR
    cfg["igroupr"] = base_addr + GICD_IGROUPR
    cfg["isenabler"] = base_addr + GICD_ISENABLER
    cfg["icenabler"] = base_addr + GICD_ICENABLER
    cfg["ispendr"] = base_addr + GICD_ISPENDR
    cfg["icpendr"] = base_addr + GICD_ICPENDR
    cfg["isactiver"] = base_addr + GICD_ISACTIVER
    cfg["icactiver"] = base_addr + GICD_ICACTIVER
    cfg["ipriorityr"] = base_addr + GICD_IPRIORITYR
    cfg["itargetsr"] = base_addr + GICD_ITARGETSR
    cfg["icfgr"] = base_addr + GICD_ICFGR
    return cfg
end

# Returns a dict describing the GIC CPU Interface register layout
# base_addr: physical base address of the GICC
proc gic_cpu_config(base_addr):
    let cfg = {}
    cfg["base"] = base_addr
    cfg["ctlr"] = base_addr + GICC_CTLR
    cfg["pmr"] = base_addr + GICC_PMR
    cfg["bpr"] = base_addr + GICC_BPR
    cfg["iar"] = base_addr + GICC_IAR
    cfg["eoir"] = base_addr + GICC_EOIR
    cfg["rpr"] = base_addr + GICC_RPR
    cfg["hppir"] = base_addr + GICC_HPPIR
    return cfg
end

# Returns a dict with the register offset and bit position to enable an IRQ
# gic: a dist config dict (from gic_dist_config)
# irq_num: the interrupt number (0-1019)
proc gic_enable_irq(gic, irq_num):
    let result = {}
    # Each ISENABLER register covers 32 IRQs
    let reg_index = irq_num / 32
    let bit_pos = irq_num % 32
    result["reg_addr"] = gic["isenabler"] + reg_index * 4
    result["bit"] = bit_pos
    result["value"] = 1 << bit_pos
    result["irq"] = irq_num
    return result
end

# Returns a list of {addr, value} pairs for GICv2 initialization
# gicd_base: physical base address of the GIC Distributor
# gicc_base: physical base address of the GIC CPU Interface
proc gic_init_sequence(gicd_base, gicc_base):
    let seq = []

    # Step 1: Disable distributor while configuring
    let s1 = {}
    s1["addr"] = gicd_base + GICD_CTLR
    s1["value"] = 0
    push(seq, s1)

    # Step 2: Set all SPIs to Group 0 (secure/FIQ)
    # IGROUPR registers: 32 IRQs per register, start at SPI range
    # Covers IRQs 32..1023 => registers 1..31
    let reg = 1
    while reg < 32:
        let s = {}
        s["addr"] = gicd_base + GICD_IGROUPR + reg * 4
        s["value"] = 0
        push(seq, s)
        reg = reg + 1
    end

    # Step 3: Disable all SPIs (clear enable bits)
    reg = 1
    while reg < 32:
        let s = {}
        s["addr"] = gicd_base + GICD_ICENABLER + reg * 4
        s["value"] = 0xFFFFFFFF
        push(seq, s)
        reg = reg + 1
    end

    # Step 4: Set all SPI priorities to default (0xA0)
    # IPRIORITYR: 4 IRQs per register (1 byte each)
    # SPIs start at IRQ 32 => byte offset 32 => register index 8
    let preg = 8
    while preg < 256:
        let s = {}
        s["addr"] = gicd_base + GICD_IPRIORITYR + preg * 4
        s["value"] = 0xA0A0A0A0
        push(seq, s)
        preg = preg + 1
    end

    # Step 5: Set all SPI targets to CPU 0
    # ITARGETSR: 4 IRQs per register (1 byte each)
    let treg = 8
    while treg < 256:
        let s = {}
        s["addr"] = gicd_base + GICD_ITARGETSR + treg * 4
        s["value"] = 0x01010101
        push(seq, s)
        treg = treg + 1
    end

    # Step 6: Set all SPIs to level-triggered
    # ICFGR: 16 IRQs per register (2 bits each), SPIs start at reg 2
    let creg = 2
    while creg < 64:
        let s = {}
        s["addr"] = gicd_base + GICD_ICFGR + creg * 4
        s["value"] = 0
        push(seq, s)
        creg = creg + 1
    end

    # Step 7: Enable distributor (Group 0 forwarding)
    let s_en = {}
    s_en["addr"] = gicd_base + GICD_CTLR
    s_en["value"] = 1
    push(seq, s_en)

    # Step 8: Configure CPU Interface — set priority mask to allow all
    let s_pmr = {}
    s_pmr["addr"] = gicc_base + GICC_PMR
    s_pmr["value"] = 0xFF
    push(seq, s_pmr)

    # Step 9: Enable CPU Interface (Group 0)
    let s_cpu = {}
    s_cpu["addr"] = gicc_base + GICC_CTLR
    s_cpu["value"] = 1
    push(seq, s_cpu)

    return seq
end

# Acknowledge an interrupt (read IAR) — returns dict with addr to read
proc gic_ack_irq(gicc_base):
    let result = {}
    result["addr"] = gicc_base + GICC_IAR
    return result
end

# End-of-interrupt (write EOIR) — returns dict with addr and value to write
proc gic_eoi(gicc_base, irq_num):
    let result = {}
    result["addr"] = gicc_base + GICC_EOIR
    result["value"] = irq_num
    return result
end

# ============================================================================
# riscv64 PLIC (Platform-Level Interrupt Controller) support
# ============================================================================

# Default PLIC base address (QEMU virt platform)
let PLIC_BASE = 0x0C000000

# PLIC register offsets (relative to base)
let PLIC_PRIORITY  = 0x000000
let PLIC_PENDING   = 0x001000
let PLIC_ENABLE    = 0x002000
let PLIC_THRESHOLD = 0x200000
let PLIC_CLAIM     = 0x200004

# PLIC layout constants
let PLIC_MAX_SOURCES  = 1024
let PLIC_MAX_CONTEXTS = 15872

# Per-context stride in the enable region
let PLIC_ENABLE_STRIDE = 0x80

# Per-context stride in the threshold/claim region
let PLIC_CONTEXT_STRIDE = 0x1000

# Returns a dict describing the PLIC register layout
# base_addr: physical base address of the PLIC
proc plic_config(base_addr):
    let cfg = {}
    cfg["base"] = base_addr
    cfg["priority"] = base_addr + PLIC_PRIORITY
    cfg["pending"] = base_addr + PLIC_PENDING
    cfg["enable"] = base_addr + PLIC_ENABLE
    cfg["threshold"] = base_addr + PLIC_THRESHOLD
    cfg["claim"] = base_addr + PLIC_CLAIM
    cfg["max_sources"] = PLIC_MAX_SOURCES
    cfg["enable_stride"] = PLIC_ENABLE_STRIDE
    cfg["context_stride"] = PLIC_CONTEXT_STRIDE
    return cfg
end

# Returns a dict with the register offset and bit to enable an IRQ
# plic: a PLIC config dict (from plic_config)
# irq_num: the interrupt source number (1-1023, source 0 is reserved)
# context: the hart context (0 = M-mode hart 0, 1 = S-mode hart 0, etc.)
proc plic_enable_irq(plic, irq_num, context):
    let result = {}
    # Enable registers: each context has PLIC_ENABLE_STRIDE bytes
    # Each 32-bit register covers 32 sources
    let context_base = plic["enable"] + context * PLIC_ENABLE_STRIDE
    let reg_index = irq_num / 32
    let bit_pos = irq_num % 32
    result["reg_addr"] = context_base + reg_index * 4
    result["bit"] = bit_pos
    result["value"] = 1 << bit_pos
    result["irq"] = irq_num
    result["context"] = context
    return result
end

# Returns a dict for disabling an IRQ on a given context
proc plic_disable_irq(plic, irq_num, context):
    let result = {}
    let context_base = plic["enable"] + context * PLIC_ENABLE_STRIDE
    let reg_index = irq_num / 32
    let bit_pos = irq_num % 32
    result["reg_addr"] = context_base + reg_index * 4
    result["bit"] = bit_pos
    # Caller must read-modify-write: clear this bit
    result["clear_mask"] = (1 << bit_pos)
    result["irq"] = irq_num
    result["context"] = context
    return result
end

# Set priority for an interrupt source
# Returns {addr, value} for the priority register write
proc plic_set_priority(plic, irq_num, priority):
    let result = {}
    # Each source has a 4-byte priority register at offset source*4
    result["addr"] = plic["priority"] + irq_num * 4
    result["value"] = priority
    result["irq"] = irq_num
    return result
end

# Set threshold for a context
# Returns {addr, value} for the threshold register write
proc plic_set_threshold(plic, context, threshold):
    let result = {}
    result["addr"] = plic["threshold"] + context * PLIC_CONTEXT_STRIDE
    result["value"] = threshold
    result["context"] = context
    return result
end

# Claim an interrupt (read the claim register for a context)
# Returns dict with the address to read
proc plic_claim_irq(plic, context):
    let result = {}
    result["addr"] = plic["claim"] + context * PLIC_CONTEXT_STRIDE
    result["context"] = context
    return result
end

# Complete an interrupt (write the IRQ number to the claim register)
# Returns {addr, value} to write
proc plic_complete_irq(plic, context, irq_num):
    let result = {}
    result["addr"] = plic["claim"] + context * PLIC_CONTEXT_STRIDE
    result["value"] = irq_num
    result["context"] = context
    return result
end

# Returns a list of {addr, value} pairs for PLIC initialization
# base_addr: physical base address of the PLIC
# num_sources: number of interrupt sources to configure (1..1023)
proc plic_init_sequence(base_addr, num_sources):
    let seq = []

    # Clamp num_sources to valid range
    if num_sources > 1023:
        num_sources = 1023
    end
    if num_sources < 1:
        num_sources = 1
    end

    # Step 1: Set all source priorities to 0 (disabled)
    let src = 1
    while src <= num_sources:
        let s = {}
        s["addr"] = base_addr + PLIC_PRIORITY + src * 4
        s["value"] = 0
        push(seq, s)
        src = src + 1
    end

    # Step 2: Disable all sources for context 0 (S-mode hart 0 = context 1)
    # Clear all enable registers for context 0 and context 1
    let ctx = 0
    while ctx < 2:
        let reg = 0
        let num_regs = (num_sources + 31) / 32
        while reg <= num_regs:
            let s = {}
            s["addr"] = base_addr + PLIC_ENABLE + ctx * PLIC_ENABLE_STRIDE + reg * 4
            s["value"] = 0
            push(seq, s)
            reg = reg + 1
        end
        ctx = ctx + 1
    end

    # Step 3: Set threshold to 0 for context 0 and context 1
    # (accept all priority levels > 0)
    let s_t0 = {}
    s_t0["addr"] = base_addr + PLIC_THRESHOLD
    s_t0["value"] = 0
    push(seq, s_t0)

    let s_t1 = {}
    s_t1["addr"] = base_addr + PLIC_THRESHOLD + PLIC_CONTEXT_STRIDE
    s_t1["value"] = 0
    push(seq, s_t1)

    return seq
end

# ============================================================================
# x86_64 Local APIC / IO-APIC support
# ============================================================================

# Local APIC register offsets
comptime:
    let LAPIC_ID = 0x20
    let LAPIC_VER = 0x30
    let LAPIC_TPR = 0x80
    let LAPIC_EOI = 0xB0
    let LAPIC_SVR = 0xF0
    let LAPIC_ICR_LO = 0x300
    let LAPIC_ICR_HI = 0x310
    let LAPIC_LVT_TIMER = 0x320
    let LAPIC_LVT_LINT0 = 0x350
    let LAPIC_LVT_LINT1 = 0x360
    let LAPIC_LVT_ERROR = 0x370
    let LAPIC_TIMER_INIT = 0x380
    let LAPIC_TIMER_CURRENT = 0x390
    let LAPIC_TIMER_DIVIDE = 0x3E0
    let IOAPIC_REGSEL = 0x00
    let IOAPIC_REGWIN = 0x10

# Returns a list of {addr, value} dicts for Local APIC initialization
# base_addr: MMIO base address of the Local APIC (typically 0xFEE00000)
proc lapic_init_sequence(base_addr):
    let seq = []

    # Step 1: Write 0xFF to TPR to mask all interrupts initially
    let s1 = {}
    s1["addr"] = base_addr + comptime(LAPIC_TPR)
    s1["value"] = 0xFF
    push(seq, s1)

    # Step 2: Write 0x1FF to SVR — enable APIC + spurious vector 0xFF
    let s2 = {}
    s2["addr"] = base_addr + comptime(LAPIC_SVR)
    s2["value"] = 0x1FF
    push(seq, s2)

    # Step 3: Mask LVT Timer
    let s3 = {}
    s3["addr"] = base_addr + comptime(LAPIC_LVT_TIMER)
    s3["value"] = 0
    push(seq, s3)

    # Step 4: Mask LVT LINT0
    let s4 = {}
    s4["addr"] = base_addr + comptime(LAPIC_LVT_LINT0)
    s4["value"] = 0
    push(seq, s4)

    # Step 5: Mask LVT LINT1
    let s5 = {}
    s5["addr"] = base_addr + comptime(LAPIC_LVT_LINT1)
    s5["value"] = 0
    push(seq, s5)

    # Step 6: Mask LVT Error
    let s6 = {}
    s6["addr"] = base_addr + comptime(LAPIC_LVT_ERROR)
    s6["value"] = 0
    push(seq, s6)

    return seq
end

# Returns a list of dicts for IO-APIC initialization
# base_addr: MMIO base address of the IO-APIC (typically 0xFEC00000)
# Configures timer (IRQ 0 -> vector 32) and keyboard (IRQ 1 -> vector 33)
proc ioapic_init_sequence(base_addr):
    let seq = []

    # Read IOAPICVER (register 1) to get max redirection entries
    # The caller should read REGSEL=1, then read REGWIN to get version/max entries
    let s_ver_sel = {}
    s_ver_sel["addr"] = base_addr + comptime(IOAPIC_REGSEL)
    s_ver_sel["value"] = 1
    s_ver_sel["comment"] = "select IOAPICVER register"
    push(seq, s_ver_sel)

    let s_ver_read = {}
    s_ver_read["addr"] = base_addr + comptime(IOAPIC_REGWIN)
    s_ver_read["action"] = "read"
    s_ver_read["comment"] = "read IOAPICVER for max redirection entries"
    push(seq, s_ver_read)

    # Configure IRQ 1 (keyboard) -> vector 33, fixed delivery, physical dest, CPU 0
    # Redirection table entry for IRQ 1: registers 0x12 (low) and 0x13 (high)
    # Low 32 bits: vector=33, delivery=fixed(000), dest_mode=physical(0), active_high, edge
    let s_kbd_lo_sel = {}
    s_kbd_lo_sel["addr"] = base_addr + comptime(IOAPIC_REGSEL)
    s_kbd_lo_sel["value"] = 0x12
    s_kbd_lo_sel["comment"] = "select IRQ 1 redirection low"
    push(seq, s_kbd_lo_sel)

    let s_kbd_lo = {}
    s_kbd_lo["addr"] = base_addr + comptime(IOAPIC_REGWIN)
    s_kbd_lo["value"] = 33
    s_kbd_lo["comment"] = "IRQ 1 -> vector 33, fixed delivery"
    push(seq, s_kbd_lo)

    # High 32 bits: destination CPU 0 (bits 24-27 = APIC ID 0)
    let s_kbd_hi_sel = {}
    s_kbd_hi_sel["addr"] = base_addr + comptime(IOAPIC_REGSEL)
    s_kbd_hi_sel["value"] = 0x13
    s_kbd_hi_sel["comment"] = "select IRQ 1 redirection high"
    push(seq, s_kbd_hi_sel)

    let s_kbd_hi = {}
    s_kbd_hi["addr"] = base_addr + comptime(IOAPIC_REGWIN)
    s_kbd_hi["value"] = 0x00000000
    s_kbd_hi["comment"] = "destination CPU 0"
    push(seq, s_kbd_hi)

    # Configure IRQ 0 (timer) -> vector 32, fixed delivery, physical dest, CPU 0
    # Redirection table entry for IRQ 0: registers 0x10 (low) and 0x11 (high)
    let s_tmr_lo_sel = {}
    s_tmr_lo_sel["addr"] = base_addr + comptime(IOAPIC_REGSEL)
    s_tmr_lo_sel["value"] = 0x10
    s_tmr_lo_sel["comment"] = "select IRQ 0 redirection low"
    push(seq, s_tmr_lo_sel)

    let s_tmr_lo = {}
    s_tmr_lo["addr"] = base_addr + comptime(IOAPIC_REGWIN)
    s_tmr_lo["value"] = 32
    s_tmr_lo["comment"] = "IRQ 0 -> vector 32, fixed delivery"
    push(seq, s_tmr_lo)

    let s_tmr_hi_sel = {}
    s_tmr_hi_sel["addr"] = base_addr + comptime(IOAPIC_REGSEL)
    s_tmr_hi_sel["value"] = 0x11
    s_tmr_hi_sel["comment"] = "select IRQ 0 redirection high"
    push(seq, s_tmr_hi_sel)

    let s_tmr_hi = {}
    s_tmr_hi["addr"] = base_addr + comptime(IOAPIC_REGWIN)
    s_tmr_hi["value"] = 0x00000000
    s_tmr_hi["comment"] = "destination CPU 0"
    push(seq, s_tmr_hi)

    return seq
end

# Returns a dict for APIC End-Of-Interrupt write
# base_addr: MMIO base address of the Local APIC
@inline
proc apic_eoi(base_addr):
    let result = {}
    result["addr"] = base_addr + comptime(LAPIC_EOI)
    result["value"] = 0
    return result
end

# ============================================================================
# aarch64 GICv3 (Generic Interrupt Controller v3) support
# ============================================================================

# GICv3 register offsets
comptime:
    let GICD_CTLR_V3 = 0x0000
    let GICD_TYPER_V3 = 0x0004
    let GICD_ISENABLER_V3 = 0x0100
    let GICD_ICENABLER_V3 = 0x0180
    let GICD_IPRIORITYR_V3 = 0x0400
    let GICD_ITARGETSR_V3 = 0x0800
    let GICR_WAKER_V3 = 0x0014
    let GICR_ISENABLER0_V3 = 0x0100

# GICD_CTLR bit definitions for GICv3
let GICD_CTLR_ARE_S = 0x10
let GICD_CTLR_ARE_NS = 0x20
let GICD_CTLR_ENABLE_G1NS = 0x02
let GICD_CTLR_ENABLE_G1S = 0x04
let GICD_CTLR_ENABLE_G0 = 0x01

# GICR_WAKER bit definitions
let GICR_WAKER_PROCESSOR_SLEEP = 0x02
let GICR_WAKER_CHILDREN_ASLEEP = 0x04

# Returns a list of dicts for GICv3 Redistributor initialization
# rdist_base: physical base address of the GICv3 Redistributor
proc gicv3_rdist_init_sequence(rdist_base):
    let seq = []

    # Step 1: Read GICR_WAKER to get current value
    let s_read = {}
    s_read["addr"] = rdist_base + comptime(GICR_WAKER_V3)
    s_read["action"] = "read"
    s_read["comment"] = "read GICR_WAKER current value"
    push(seq, s_read)

    # Step 2: Clear ProcessorSleep bit (bit 1) to wake the redistributor
    # Caller should read current value, clear bit 1, then write back
    let s_wake = {}
    s_wake["addr"] = rdist_base + comptime(GICR_WAKER_V3)
    s_wake["clear_bits"] = GICR_WAKER_PROCESSOR_SLEEP
    s_wake["comment"] = "clear ProcessorSleep (bit 1) to wake redistributor"
    push(seq, s_wake)

    # Step 3: Poll until ChildrenAsleep (bit 2) clears
    let s_poll = {}
    s_poll["addr"] = rdist_base + comptime(GICR_WAKER_V3)
    s_poll["action"] = "poll"
    s_poll["poll_mask"] = GICR_WAKER_CHILDREN_ASLEEP
    s_poll["poll_value"] = 0
    s_poll["comment"] = "wait for ChildrenAsleep (bit 2) to clear"
    push(seq, s_poll)

    return seq
end

# Returns a list of dicts for GICv3 Distributor initialization
# dist_base: physical base address of the GICv3 Distributor
proc gicv3_dist_init_sequence(dist_base):
    let seq = []

    # Step 1: Enable ARE_NS and ARE_S in GICD_CTLR
    # This enables affinity routing (required for GICv3)
    let s_are = {}
    s_are["addr"] = dist_base + comptime(GICD_CTLR_V3)
    s_are["value"] = GICD_CTLR_ARE_S + GICD_CTLR_ARE_NS
    s_are["comment"] = "enable ARE_S and ARE_NS for affinity routing"
    push(seq, s_are)

    # Step 2: Enable Group 1 Non-Secure interrupts
    let s_grp = {}
    s_grp["addr"] = dist_base + comptime(GICD_CTLR_V3)
    s_grp["value"] = GICD_CTLR_ARE_S + GICD_CTLR_ARE_NS + GICD_CTLR_ENABLE_G1NS
    s_grp["comment"] = "enable Group 1 Non-Secure + affinity routing"
    push(seq, s_grp)

    return seq
end

# Returns a list of register/value dicts for GICv3 CPU interface init
# GICv3 uses system registers instead of memory-mapped CPU interface
proc gicv3_cpu_init_sequence():
    let seq = []

    # Step 1: Set ICC_SRE_EL1 to enable system register access
    let s_sre = {}
    s_sre["register"] = "ICC_SRE_EL1"
    s_sre["value"] = 0x07
    s_sre["comment"] = "enable system register access (SRE=1, DFB=1, DIB=1)"
    push(seq, s_sre)

    # Step 2: Set ICC_PMR_EL1 = 0xFF (lowest priority mask, accept all)
    let s_pmr = {}
    s_pmr["register"] = "ICC_PMR_EL1"
    s_pmr["value"] = 0xFF
    s_pmr["comment"] = "set priority mask to accept all priorities"
    push(seq, s_pmr)

    # Step 3: Set ICC_IGRPEN1_EL1 = 1 (enable Group 1 interrupts)
    let s_grp = {}
    s_grp["register"] = "ICC_IGRPEN1_EL1"
    s_grp["value"] = 1
    s_grp["comment"] = "enable Group 1 interrupts"
    push(seq, s_grp)

    return seq
end

# ============================================================================
# Architecture dispatcher
# ============================================================================

# Initialize the appropriate interrupt controller for the given architecture
# arch: "x86_64", "aarch64", or "riscv64"
# base_addr: base address (used as vector_base for x86_64 PIC,
#            GICD base for aarch64, PLIC base for riscv64)
# Returns a dict with controller info and initialization sequence
proc interrupt_init(arch, base_addr):
    let result = {}
    result["arch"] = arch

    if arch == "x86_64":
        result["type"] = "PIC"
        result["sequence"] = pic_remap_sequence(base_addr)
        result["vector_base"] = base_addr
        return result
    end

    if arch == "aarch64":
        result["type"] = "GIC"
        let gicd_base = base_addr
        let gicc_base = base_addr + 0x10000
        result["gicd"] = gic_dist_config(gicd_base)
        result["gicc"] = gic_cpu_config(gicc_base)
        result["sequence"] = gic_init_sequence(gicd_base, gicc_base)
        return result
    end

    if arch == "riscv64":
        result["type"] = "PLIC"
        result["plic"] = plic_config(base_addr)
        result["sequence"] = plic_init_sequence(base_addr, 127)
        return result
    end

    result["type"] = "unknown"
    result["error"] = "Unsupported architecture: " + arch
    result["sequence"] = []
    return result
end
