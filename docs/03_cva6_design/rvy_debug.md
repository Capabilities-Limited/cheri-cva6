# Y Debug (Sdext) Implementation

This documentation describes the integration of the core with RVY's debug Sdext extension, describing how to enable debugging of CHERI features, such as capability registers.

See [cheri_debug.md][debug-user] for instructions on how to use the debug features.

The debug support spans the core itself and the submoduled riscv-dbg, which is a [Capabilities Limited fork][capltd-riscv-dbg] of the [parent repository][pulp-riscv-dbg] hosted as part of the pulp-platform.

Note that although Sdtrig is listed as orthogonal to CHERI, Sdtrig has not been tested with CHERI in CVA6-CHERI.
The CVA6 Sdtrig implementation currently has known bugs aside from CHERI, e.g. not supporting superscalar.

## Requirements

These are the requirements drawn from the [RVY debug spec (version 0.9.10.1)][rvy-debug-spec]:

Access to capability registers is provided via the program buffer.

Access to capabilities in memory is provided via the program buffer.

## Abstract commands

Abstract commands are not extended with CHERI support: these are marked as optional in the specification.

## Program buffer

From the specification, the following are required of the program buffer when implementing CHERI debug:
- "`hartinfo` must be implemented": This is implemented in the debug module's [dm_csrs.sv][hartinfo-dbg] though the read-only value is populated in CVA6's own [ariane_pkg.sv][hartinfo-cva6].
- "`hartinfo.nscratch` is at least 1 and the `dscratch0 (RVY)` register is implemented": CVA6 sets `nscratch` to two and implements two registers: see [the `hartinfo` definition][hartinfo-cva6].
- "`hartinfo.datasize` is at least 1 and `hartinfo.dataaccess` is 0": :warning: This is not the case for CVA6, which sets `hartinfo.dataaccess` to be 1, since the debug module is memory mapped. However, this is in the process of being changed as a [PR][dataaccess-pr] to the spec. `datasize` is 2.
- "`abstractcs.progbufsize` is at least 4 if `dmstatus.impebreak` is 1 or at least 5 if `dmstatus.impebreak` is 0": [`progbufsize`][progbufsize] is 8 and [`dmstatus.impebreak`][dmstatus] is 0.

## Debug mode entry

The core can enter debug mode as a result of:
- an `ebreak` instruction with the current mode's `dcsr_q.ebreak{m,s,u}` set
- A debug request from the external debugger
- A completed single step
- (Currently unsupported with CHERI): a debug trigger

In these scenarios:
- `dpc` is set to the PCC of the instruction to run on debug return
- `dddc` is set to the current `ddc`
- PCC is set to a root capability with address set to the debug mode entry point: `DmBaseAddress` + `HaltAddress`, as specified in the included CVA6 config, e.g. [cv64a6_imafdczcheri_sv39_hpdcache_wb_config_pkg.sv][cva6-zcheri-cfg]
- PCC's Pointer Mode is set to capability mode
- `ddc` is set to a root capability with address set to `ddc`'s current address.

In addition, debug mode can be "re-entered" as a result of:
- an exception from within debug mode
- an `ebreak` from within debug mode, typically at the end of a program buffer program

In both of these "re-entry" cases, only the PCC is updated, not the `dpc`, `dddc`, or `ddc`. :warning: If CHERI checks are enabled in debug mode, DDC should change to being set to a root cap in this case, to avoid the debug module reaching an irrecoverable state if the Debug ROM relies on DDC.
The Pointer Mode of the `ebreak` final instruction must be saved so that it can be restored for the subsequent program buffer execution, as required by the RVY debug spec.
This is done by selecting entry-point based on the reason for re-entering debug mode.
`DmBaseAddress` + `ExceptionAddress`, as specified in the included CVA6 config, e.g. [cv64a6_imafdczcheri_sv39_hpdcache_wb_config_pkg.sv][cva6-zcheri-cfg], with offsets of 0 (exception from capmode), 8 (exception from intmode), 16 (ebreak from capmode), 24 (ebreak from intmode). :warning: There is currently a bug with exception entry point offset calculation.

This information is communicated to the frontend by the extended `set_debug_pc_o` signal.

## Debug mode operation
During debug, the PC (and PCC) operate as normal and PC-relative instructions are allowed.
PCC Checks are disabled: both the fetch PCC checks in [issue_read_operands.sv][iro] and the Access System Registers checks in [csr_regfile.sv][csr-regfile].
CHERI memory access checks are also disabled. :warning: This behaviour is unnecessary and subject to future change.

### `dpc`

`dpc` is implemented in [csr_regfile.sv][csr-regfile].
It is initialised to a root capability. :warning: Though unobservable, this is unnecessary, and should be changed to a null capability.
However, its value is not observable until debug mode is entered, and is continuously updated to match the PCC when outside debug mode, meaning on debug entry it is set to the PCC of the breaking instruction.
:warning: This behaviour is subject to change, preferring setting it only on entering debug mode as its value is visible via RVFI.
On `DRET`, `dpc` is unsealed and installed as the new PCC.

### `dscratch{0,1}`

`dscratch0` and `dscratch1` are implemented as YLEN-widened debug-only registers in [csr_regfile.sv][csr-regfile].
They are initialised to null capabilities.

### `drootcsel`

`drootcsel` is implemented in [csr_regfile.sv][csr-regfile] as a WARL constant zero register: there is only one root cap in CVA6-CHERI.

### `drootc`

`drootc` is implemented in [csr_regfile.sv][csr-regfile] as a WARL register that has the root capability as its constant value for all but the Pointer Mode (P) bit.
The P bit is populated based on the int_mode of the currently running instruction, i.e. the CSR instruction that is accessing `drootc`.
This enables the CSR to reflect the correct mode, even directly following a mode switch.
Though the software model is that the Pointer Mode stored in `drootc` determines the Pointer Mode in debug entry, CVA6-CHERI instead always enters debug mode in capability mode, and it is the Debug ROM's responsibility to ensure the correct Pointer Mode is entered before starting the program buffer.
See the [Debug mode entry](#debug-mode-entry) section.

### `dddc`

`dddc` is implemented in [csr_regfile.sv][csr-regfile].
It is a YLEN-new debug-only CSR.
It is reset to the null capability.
Its value is not observable until debug mode is entered, and is continuously updated to match the `ddc` when outside debug mode, meaning on debug entry it is set to the `ddc` of the breaking instruction.
:warning: This behaviour is subject to change, preferring setting it only on entering debug mode as its value is visible via RVFI.
On `DRET`, `dddc` is restored into `ddc`.

## `DRET`

CVA6 implements `DRET` to return from debug mode.
The behaviour is implemented in [csr_regfile.sv][csr-regfile].
`dpc` is unsealed and installed as PCC.
`ddc` is restored from `dddc`.

## Debug ROM

The [debug ROM][debug-rom] is extended for RVY in the following ways:
- Entry points are added for the different possibilities described in [Debug mode entry](#debug-mode-entry).
- `ymodeswy` and `ymodeswi` instructions are added according to the requirements that CSR saves and restores must be in capmode (to ensure CHERI metadata is fully transferred) and memory accesses must be in intmode (to use DDC and allow dereference via x0 for the one scratch case :warning: Use of DDC is currently unnecessary due to the disabling of CHERI memory checks in debug mode)
- Stores to the debug module are added to record the Pointer Mode indicated by the entry point for re-entry cases.
- Exception handlers restore the indicated Pointer Mode before ebreak, so that the re-entry handler will save the required mode.
- Code is added to install the required Pointer Mode (intmode after reset, otherwise whatever the last progbuf program finished in) based on reading flags from the debug module on the path to `whereto`, e.g. to enter the program buffer.

## Debug module

The debug module has added state in [dm_mem.sv][dm-mem] for the Pointer Mode each hart last finished the program buffer in, either via an exception or ebreak.
Due to the scarce registers available in the debug ROM, different addresses rather than different store values are used to differentiate intmode (offset 0x120) from capmode (offset 0x128).
The debug module indicates whether the last mode was intmode in bit 2 of the value read in flags.

[debug-user]: ../05_cva6_apu/cheri_debug.md
[rvy-debug-spec]: https://github.com/riscv/riscv-cheri/releases/download/v0.9.10.1-ar20261013/riscv-cheri-debug-0.9.10.1-ar20261013.pdf
[capltd-riscv-dbg]: https://github.com/Capabilities-Limited/riscv-dbg/tree/RVY-cva6
[pulp-riscv-dbg]: https://github.com/pulp-platform/riscv-dbg
[hartinfo-dbg]: https://github.com/Capabilities-Limited/riscv-dbg/blob/7fbcff1d606d2193be6517ac1b736c9f85983e5e/src/dm_csrs.sv#L313
[hartinfo-cva6]: ../../core/include/ariane_pkg.sv#L93-L100
[dataaccess-pr]: https://github.com/riscv/riscv-cheri/pull/1341
[progbufsize]: https://github.com/Capabilities-Limited/riscv-dbg/blob/7fbcff1d606d2193be6517ac1b736c9f85983e5e/src/dm_pkg.sv#L22
[dmstatus]: https://github.com/Capabilities-Limited/riscv-dbg/blob/7fbcff1d606d2193be6517ac1b736c9f85983e5e/src/dm_csrs.sv#L232
[csr-regfile]: ../../core/csr_regfile.sv
[iro]: ../../core/issue_read_operands.sv
[cva6-zcheri-cfg]: ../../core/include/cv64a6_imafdczcheri_sv39_hpdcache_wb_config_pkg.sv
[debug-rom]: https://github.com/Capabilities-Limited/riscv-dbg/blob/RVY-cva6/debug_rom/debug_rom.S
[dm-mem]: https://github.com/Capabilities-Limited/riscv-dbg/blob/RVY-cva6/src/dm_mem.sv
