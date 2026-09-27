## boot.sage — SageBoot, the second-stage bootloader for the classic ESP32.
##
## Flashed at 0x1000. The ESP32 ROM bootloader loads this image and jumps to its
## entry, which is the literal-free `j` in hal/entry.S; that establishes a1/a15
## and calls reset_handler in hal/startup.c, which takes over the watchdogs,
## clears .bss, copies .data and then calls main() below.
##
## This is still a stub. `nil` is the no-op statement in SageLang -- `pass` is
## not a statement in this language and the compiler rejects it, which is why
## this file did not compile before:
##   error: unknown name 'pass' in compiled code
##
## The `pass` -> `nil` fix is what makes `build.sh boot` and `build.sh all` work
## at all. What belongs here next is the real stage-2 job, in this order:
##   1. walk the partition table (gen_partitions.py writes it at 0x8000) and pick
##      the app slot, so a corrupt or empty slot is reported rather than jumped to
##   2. validate the SageOS image: image header, segment count, and the SHA-256
##      of the payload
##   3. hand off, using the existing hw.jump primitive
##
## The partition table and app slot addresses must match gen_partitions.py and
## build.sh (`sagelet_os` is linked to load at 0x10000).

proc main():
    nil

main()
