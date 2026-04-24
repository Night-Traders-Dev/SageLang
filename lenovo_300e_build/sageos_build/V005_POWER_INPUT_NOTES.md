# SageOS v0.0.5 Power/Input Notes

## Fixed

- Firmware input is now exclusive when available.
- PS/2 polling is fallback-only.
- This prevents duplicate modifier-state behavior that caused random upper/lowercase changes.

## Added

- `shutdown` / `poweroff`
  - Attempts ACPI S5 using FADT + DSDT `_S5_`.
  - Does not hang forever if unsupported.

- `suspend`
  - Attempts ACPI S3 using DSDT `_S3_`.
  - This is experimental.

- `fwshutdown`
  - Direct UEFI RuntimeServices ResetSystem shutdown attempt.
  - Kept separate because it may hang on the Lenovo firmware.

## Lid close / wake status

Full automatic lid-close suspend and lid-open wake needs native ACPI event support:

- ACPI SCI interrupt routing
- GPE enable/status registers
- Lid device `_LID` method evaluation
- EC query/event support on Chromebooks
- AML interpreter or a targeted EC/GPE implementation

The `suspend` command is the first foundation. Real lid-triggered suspend/wake is the next driver milestone.
