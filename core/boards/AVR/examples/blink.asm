; ATmega328P blink -- toggles PORTB5 (Arduino Uno onboard LED).
; Assembles to Intel (.hex) via the SageLang AVR assembler.

.org 0x0000
    ldi r16, 0x20        ; bit 5 = LED pin
    out DDRB, r16        ; DDRB = pin 5 as output
loop:
    out PORTB, r16       ; LED on
    call delay
    out PORTB, r0        ; LED off (r0 = 0 after clear)
    rjmp loop

delay:
    ldi r18, 0xFF        ; outer loop counter
delay_outer:
    ldi r19, 0xFF        ; inner loop counter
delay_inner:
    dec r19
    brne delay_inner
    dec r18
    brne delay_outer
    ret