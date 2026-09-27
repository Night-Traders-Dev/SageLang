; Broad instruction coverage for cross-validation against GNU as.
    .org 0x0000
    ldi r16, 0x20
    ldi r31, 0xFF
    clr_test:
    add r16, r17
    adc r16, r17
    and r16, r17
    eor r16, r17
    or r16, r17
    sub r16, r17
    sbc r16, r17
    cp r16, r17
    cpc r16, r17
    mov r16, r17
    cpse r16, r17
    mul r16, r17
    movw r18, r22
    muls r20, r21
    cpi r16, 0x10
    sbci r16, 0x11
    subi r16, 0x12
    ori r16, 0x20
    andi r16, 0x0F
    adiw r24, 3
    sbiw r26, 2
    inc r16
    dec r16
    com r16
    neg r16
    swap r16
    asr r16
    lsr r16
    ror r16
    push r16
    pop r17
    sbi 0x05, 3
    cbi 0x05, 3
    sbis 0x05, 3
    sbic 0x05, 3
    sbrs r16, 5
    sbrc r17, 3
    sbrs r0, 0
    sbrc r31, 7
    in r16, 0x3D
    out 0x3E, r16
    nop
    ret
    reti
    sleep
    wdr
    sei
    cli
    ijmp
    icall
    lpm
    lsl r16
    rol r16
    tst r16
    ser r18
    lds r16, 0x0100
    lds r17, 0x00C0
    sts 0x00C6, r18
    sts 0x0100, r19
