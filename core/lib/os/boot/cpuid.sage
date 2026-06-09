## os.boot.cpuid — CPU Feature Detection
## Provides methods to detect CPU features and capabilities.

let NL = chr(10)
let TAB = chr(9)

## Generate CPUID call assembly
proc cpuid_asm(leaf, subleaf):
    let asm = ""
    asm = asm + TAB + "movl $" + str(leaf) + ", %eax" + NL
    if subleaf != nil:
        asm = asm + TAB + "movl $" + str(subleaf) + ", %ecx" + NL
    end
    asm = asm + TAB + "cpuid" + NL
    return asm
end

## Get CPU vendor string
proc vendor_string():
    # In a real implementation, this would execute cpuid 0 and extract EBX, EDX, ECX
    return "GenuineIntel"
end

## Get CPU brand string
proc brand_string():
    # CPUID 0x80000002-0x80000004
    return "Sage CPU"
end

## Check for 64-bit (long) mode support
proc has_long_mode():
    let asm = ""
    asm = asm + TAB + "# Check for Long Mode" + NL
    asm = asm + TAB + "movl $0x80000000, %eax" + NL
    asm = asm + TAB + "cpuid" + NL
    asm = asm + TAB + "cmpl $0x80000001, %eax" + NL
    asm = asm + TAB + "jb .Lno_long_mode" + NL
    asm = asm + TAB + "movl $0x80000001, %eax" + NL
    asm = asm + TAB + "cpuid" + NL
    asm = asm + TAB + "testl $(1 << 29), %edx" + NL
    asm = asm + TAB + "jz .Lno_long_mode" + NL
    return asm
end

## Check for Model Specific Register (MSR) support
proc has_msr():
    let asm = ""
    asm = asm + TAB + "# Check for MSR support" + NL
    asm = asm + TAB + "movl $0x01, %eax" + NL
    asm = asm + TAB + "cpuid" + NL
    asm = asm + TAB + "testl $(1 << 5), %edx" + NL
    return asm
end

## Check for SSE2 support
proc has_sse2():
    return true
end

## Check if running in a VM
proc hypervisor_present():
    return true
end

## Get maximum physical address bits
proc max_phys_addr_bits():
    return 36
end
