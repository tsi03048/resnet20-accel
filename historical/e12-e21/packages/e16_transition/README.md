# E16 · Transition RTL / Option A

Diagnostic fixed-shape SystemVerilog. Two separately elaborated Conv cores are sequentially scheduled; this is NOT one time-shared physical MAC. Actual synthesis/resource use is unverified.

## Run

```bash
VERILATOR=/path/to/verilator bash run.sh
```

Requires Verilator, GCC C++20, make, Python3. Used environment: PyPI verilator5.48.0, --version rev vUNKNOWN-built20260516-4e853d8, simulator banner5.49. The C++20/PCH settings match the used GCC wheel environment. Tools/compiled executables/generated C++ are excluded.

## Contract

Conv1: Cin=C, Cout=2C, stride2, PAD1, kernel3. Conv2: Cin=Cout=2C, stride1, PAD1. H/W are equal, even powers of two in verified configs. Static parameters, not runtime descriptor. 16-bit addresses/index and INT32 bias/accumulator; use inputs whose accumulator does not overflow. Bias is latched at block command. Input/weight memory stable while busy.

H=sat8(ReLU(RNE(acc1/4))); M=sat8(RNE(acc2/4)); Y=sat8(ReLU(signext9(M)+signext9(S))). All activation scales equal S, zero points0, weight scale1/4, bias unit S/4. Diagnostic constants, no real checkpoint or perchannel quantization.

Option A: output channel range C/2 <= co < C/2+C reads X[co-C/2,2oy,2ox]. Other channels create code0 without reading X. Conv padding similarly suppresses Input read but retains Weight read/logical MAC term. Quotient/index expressions for shortcut use static power-of-two shifts/masks.

Memory A=xmem keeps X, B=amem first holds H then Y after Conv2 drain, C=fmem holds M. Add uses synchronous read capture, next-edge9-bit sum, held output, and writes B at y fire. Block response follows final Y sink acceptance/local write. This is not external DMA/DDR/CPU visibility completion.

load_sel0=X,1=W1,2=W2; load_we&&load_ready accepts valid-range element writes. prepared is an external guarantee of complete X/weights/bias preparation; no internal coverage tracker or error CSR. Reset cancels controls/valids; it does not erase arrays. External owner drops prepared and reloads after cancellation.

## Actual tests

- Small C2 H4 -> C4 H2: four numeric vectors, repeated X/W reuse, reset at Conv1/Conv2/Add read/heldY/heldresponse, recovery. Normal7, cancelled5. Random y stall and final-y directed hold.
- Stage1->2 C16 H32 -> C32 H16: one complete signed-random block, K144/288, 8,192outputs.
- Stage2->3 C32 H16 -> C64 H8: one complete signed-random block, K288/576, 4,096outputs.
- All configurations compare request addresses/tags/padding, term order, acc1/H/acc2/M, materialized OptionA skip, Y/index/last, held payload/response, X preservation/B=Y/C=M, local writes and completion boundaries.
- Missing reference file is checked before readmemh. Negative test hides one vector temporarily, verifies simulator abort, always restores it.

Full simulations are results/simulation_0/1/2.log. Full-size trials are one vector each, not exhaustive seeds/reset coverage. summary.json preserves counts including accepted tokens from cancelled jobs, which are not normal completion. VCD is separate small-case first100us, TRACE WINDOW ONLY is not full regression evidence.

Limits: no trained checkpoint/BN/perchannel rescale/accuracy; no hardware synthesis, BRAM inference/modes/read-during-write, DSP/STA/board or performance evidence; no arbitrary latency, outstanding bus traffic, DMA/cache/CDC or four-state X/Z proof. Main/shortcut capture is synchronous and serialized; independent variable-latency branch queues are not implemented. Full-size source passes do not close all product verification requirements.
