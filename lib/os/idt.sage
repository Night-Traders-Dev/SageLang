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
