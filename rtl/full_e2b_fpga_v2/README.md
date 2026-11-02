# FPGA v2 source set

Final physical top: **full_model_timed**. Tutorial: [E8-D](../../docs/full_fpga_v2.md).

| File | Role |
| --- | --- |
| full_model_timed.sv | Native interface plus identity hold buffers; no values tied off |
| full_model.sv | All 30 operations, queued loader, registered descriptors/addresses |
| control_rom.svh | Precomputed geometry from frozen E2-B manifest; no Golden outputs |
| sync_bram.sv, weight_bram.sv | Two-cycle reads; 262144+8192 Weight words, separate coefficient RAMs |
| feature_ram.sv | Three logical feature banks in true dual-port BRAM |
| mul_serial.sv, rne_serial.sv | Exact signed products, one RNE, clipping |
| input_hold.sv | Explicit identity LUT1 delay; timing must be rechecked after changes |
| full_model_ooc.sv | Earlier clock-buffer diagnostic fixture; **not** the final flow top |

The shared `rtl/full_e2b_v1/argmax10.sv` is also compiled. `board/zedboard/build_full.tcl` lists the actual physical sources. RTL simulation additionally compiles `tb/full_e2b_fpga_v2/LUT1.sv`, an exact zero-delay truth-table model. That test model is never included in Vivado synthesis.

`python -m tools.v2_control_rom` regenerates only the descriptor include. The integer constants and Golden remain the frozen E2-B package. No memory is initialized with intermediate Golden data.
