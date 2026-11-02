# E18 · Integrate requantization into Option A Transition

Educational RTL: E17 requant_join replaces both Conv postprocessing and Residual Add in E16. Two separately elaborated Conv cores execute sequentially; not a physically shared MAC. Symmetric activation zero points0. Conv2 M is still stored as saturated signed INT8 before Add. No wide-acc/skip fusion across that boundary.

## Numeric contract

H=clip8(ReLU(RNE(acc1*N1[channel]/2^s1[channel]))).
M=clip8(RNE(acc2*N2[channel]/2^s2[channel])).
Y=clip8(ReLU(RNE((M*Nm[channel]+OptionA(X)*Ns[channel])/2^sa[channel]))).
Add rounds once after the wide sum. Zero-channel skip is centered integer0; it does not erase Main.

External coefficient arrays are complete before block command. At block cmd fire, bias1/bias2 and all7coefficient arrays (N1,N2,Nm,Ns,s1,s2,sa) are snapshotted into registers. Each Conv captures its table again at its internal cmd fire. Channel lookup uses Conv co or Add destination co, and the requant unit metadata carries output index/last. Source arrays may change after external cmd acceptance without changing the accepted job. No coefficient RAM latency/version CSR/atomic shadow swap/load completeness tracker.

N ports unsigned16, shifts0..31; numerical behavior uses E17's49-bit products/64-bit sum/RNE/signed INT8 clipping. This does not prove upstream32-bit accumulator overflow safety. Varied tables are diagnostic arithmetic stress patterns; they are not calibration results or guaranteed coherent trained-model scales.

## Baseline and actual tests

Compatibility settings: Conv1/2 N1 shift2; Add Nm=Ns=1 shift0. Python regenerates vectors and compares acc1/acc2/H/M/skip/Y byte-for-byte with bundled E16 baseline files:4small vectors and1each Stage12/Stage23. RTL compares every value to these exact expectations.

Small C2 H4->C4 H2:6numeric jobs (4baseline,2varied/repeated table pattern),2repeated baseline jobs,1recovery =9normal;6reset cancellations at Conv1,Conv2,zero Add capture,heldY,heldresponse,central real-skip capture. Last case accepts earlier zero-channel outputs before cancellation. The accepted total includes tokens from cancelled jobs; cancellation is not success.

Stage12 C16 H32->C32 H16 and Stage23 C32 H16->C64 H8:2complete jobs each, one baseline and one varied signed-random case. Every request address/tag/padding, term order, wide accumulator, H/M/skip/Y, output hold/index/last, X preservation/B=Y/C=M/local write and completion order is compared.

TB sets external coefficient arrays to0 after command, including before Conv2/Add, while reference retains the accepted settings. Repeated jobs restore coefficients before their next command. This checks both isolation and use of new settings on the next job. It does not implement a hardware banked configuration protocol.

## Run and files

```bash
VERILATOR=/path/to/verilator bash run.sh
```

Python3, Verilator, GCC C++20 and make required. Used PyPI5.48.0, binary --version rev vUNKNOWN-built20260516-4e853d8, simulation banner5.49. GCC PCH/C++20 flags match that wheel environment. baseline_e16/ contains frozen vector files used by the compatibility assertions; do not edit them to fix a mismatch. reference/ contains new vectors and perchannel tables.

results/simulation_0/1/2.log are full regressions. small_block_window.vcd is a separate small-case first100us run, not full evidence. summary/source_sha256/toolchain.json record counts/identity. Missing reference fails immediately; a negative test verifies this and restores the file. No tool binaries, generated C++ objects or simulator executables included.

## Limits

No trained checkpoint/calibration/exporter/accuracy, nonzero activation centering, coefficient RAM response protocol, FIFO/reordering, DMA/cache/CDC, arbitrary shape or4-state proof. E14Identity/E13Stem top wrappers are not modified or regressed here. E17standalone zero-point capability is not enabled by this Top. No FPGA synthesis/BRAM/DSP/STA/board/performance evidence. Static power-of-two spatial sizes, two Conv cores, sequential local memory model; selected regression cases only.
