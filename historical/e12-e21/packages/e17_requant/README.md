# E17 · Requantization / common-denominator Add unit

Standalone diagnostic SystemVerilog. This unit is not yet integrated into E16 Conv/Transition. It does not load a trained checkpoint, select calibration scales or generate approximation coefficients.

## Contract

Main/Skip input: signed32 centered values. Nmain/Nskip: unsigned16 (0..65535); shift:0..31. Numerator v=main*Nmain+(add_mode?skip*Nskip:0). Both branches use one common denominator2^shift. RNE is applied ONCE after wide sum. Then add signed8 output_zero, optional ReLU max(code,output_zero), signed8 saturation[-128,127]. Caller centers codes before input and aligns coefficients to the agreed denominator. Negative multipliers/left shifts/separate branch rounding are not supported.

Two32×17signed products use49bits, sign extend64, sum64. Bounds of the allowed operands keep numerator magnitude below2^48 and leave room for signed8 zero addition. This does not prove INT32 Conv accumulator safety before the unit. RNE shift0 bypasses remainder/half processing.

Coefficients/channel/last belong to each input token. Caller supplies the right channel's table entry. There is no coefficient RAM/version tracker. Result code/channel/last are registered at input fire and held until output fire. One entry, conservative ready=!out_valid&&!rst; no simultaneous consume/replace throughput claim. Reset cancels an accepted held result, clears valid, and permits recovery. This unit alone has no frame completion response.

## Reproduce

```bash
VERILATOR=/path/to/verilator bash run.sh
```

Needs Verilator, GCC C++20, make, Python3. Used PyPI distribution5.48.0, --version rev vUNKNOWN-built20260516-4e853d8, simulation banner5.49. C++20/GCC PCH options match used wheel environment. Tool binaries/generated C++/executables excluded.

reference/make_vectors.py uses unbounded Python integers and sign/absolute quotient/remainder rounding. RTL uses signed floor shift/lowbit remainder/parity. Python vectors:7,508 including divide4 exhaustive accumulator codes-1024..1024 (2,049cases), extreme signed operands, shift0/31, unsigned multiplier0/65535, nonzero signed zero points/ReLU, single-round Add witnesses and5,000seed17017 random inputs with4channel coefficient entries.

Results:7,508vectors plus one recovery output;7,510accepted tokens,7,509outputs,1reset cancellation,15,015hold checks. Each output code/channel/last checked. Live config changes while a registered result is held. Missing or malformed reference immediately fails; negative tests confirm both paths and restore the file. Result log and summary are separate from partial first10us VCD execution (TRACE WINDOW ONLY).

Important limitation: arbitrary perchannel tables are supplied at the interface, not fetched from a calibrated model. No full Conv/Residual/Transition numeric integration yet. No coefficient-swap job generation, actual-model accuracy, arbitrary affine zero centering, bus/DMA/CDC, FPGA synthesis/STA/BRAM/DSP/board or physical performance. Selected simulator tests, not all32bit input combinations or4-state X/Z proof.
