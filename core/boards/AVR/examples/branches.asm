    .org 0x0000
    ldi r16, 0x00
    rjmp fwd
back:
    rjmp back
fwd:
    rcall sub1
    breq fwd
    brne fwd
    brcs fwd
    brcc fwd
    brlo fwd
    brsh fwd
    brlt fwd
    brge fwd
    brmi fwd
    brpl fwd
    brvs fwd
    brvc fwd
    brhs fwd
    brhc fwd
    sbrs r16, 2
    sbrc r16, 2
    sbis 0x05, 1
    sbic 0x05, 1
    jmp sub1
    call sub1
    rjmp done
sub1:
    ldi r17, 0x55
    ret
done:
    rjmp done
