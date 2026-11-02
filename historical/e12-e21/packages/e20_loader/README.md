# E20 · Ordered native RTL Loader and commit/start gate

E19validate returns verified integer lists and Manifest identity in memory. software/build_vectors.py validates packages against frozen fixture pins, checks separate E18input/expected-vector audit hashes, encodes an ordered32bit write stream and emits metadata. It does not blindly trust a JSON status=PASS string. Package Shape must also be routed to the matching fixed hardware instance.

## Hardware protocol

Begin(validated flag,Manifest digest,generation,Cin,H) -> ordered writes -> Commit -> Start(generation) -> outputs -> response -> IDLE(unprepared). Begin may restart a nonrunning load/error/ready transaction and discards its progress. It cannot interrupt RUN/RESP. Reset cancels both Loader and Core, clears preparation/error/identity but does not erase every memory array.

Role order:0Input,1Weight1,2Weight2,3Bias1,4Bias2,5N1,6N2,7Nm,8Ns,9s1,10s2,11sa. Each role begins at element address0 and increases by1 through the exact fixed length. Gaps/duplicates/out-of-order writes reject. No random writes/bitmap. Input and Weight transport uses raw unsigned8two's-complement bits zero-extended32; Bias uses raw32bit two's-complement; N range0..65535,shift0..31. Invalid writes are not forwarded to Core.

All handshakes are same-clock native ready/valid. Commit has priority over Write, Begin has priority over both. Host serializes transactions and must keep an offered unaccepted payload stable. No per-write generation tag,old asynchronous bus-response draining,AXI/APB/DMA/CDC or packet integrity checking is implemented.

Prepared stays0 until the accepted full sequence is committed. Core writes are synchronous local memory updates at write fire; coefficient registers update on their fire. After final write and later Commit, ready permits Start. This local write model has no outstanding external write response. Native load buffers are blocked during execution and while response is held. Completion returns toIDLE and requires fresh Begin/full load/Commit before the next job.

Error codes:1host says not validated,2role/order,3address/order,4data width/range,5incomplete commit,6stale command generation,7wrong fixed Shape. Error is sticky until reset or a new Begin. Start with wrong generation is consumed as rejection, not forwarded to Core.

## Trust and identity limits

RTL does NOT verify JSON,SHA256,source provenance,accumulator bounds or the truth of host_validated. Digest is a captured identity label,not hardware proof that transported bytes match it. E19software checks and trusted transport/driver remain assumptions. Changing a within-range Weight/Bias in transit is not detected by ordered counting. Production integrity/checksum/readback and authenticated provenance are outside scope.

Generation comparison rejects a mismatching command. It does NOT enforce monotonic IDs,uniqueness or protection if Host reuses an old generation,especially across reset. Fixture numbers identify cases and may repeat after reload. A production Host must manage generations and drain pending traffic. These tests do not prove universal replay protection.

## Reproduce

```bash
VERILATOR=/path/to/verilator bash run.sh
```

Needs Python3,Verilator,GCC C++20,make. Used PyPI5.48.0,binary rev vUNKNOWN-built20260516-4e853d8,simulation banner5.49; wheel environment GCC PCH/C++20 options included. Tools/generatedC++/executables excluded.

Bridge emits4streams:smallcompat/smallvaried284writes each,Stage1230,496writes,Stage2364,064writes. Software invalid Manifest/input audit cases fail before a write stream is emitted. Full RTL regressions are results/simulation_0/1/2.log; separate small_window.vcd is first100us only,TRACE WINDOW ONLY does not mean full pass.

Small normal4jobs,2running/held-response cancellations,1reset-during-partial-load and10rejectedtransactions. Full Stage12 andStage23 each1complete varied job. Comparisons:request address/tag/padding,term order,acc1/H/acc2/M/skip/Y,index/last/hold,X preservation,B=Y,C=M,localwrite,prepared gating,transaction identity and response ordering. Not all full-size error/reset positions are tested.

No actual trained checkpoint/calibration/accuracy,FPGA synthesis/BRAM/DSP/STA/board/performance,coefficientRAM latency/driver/bus failures,four-state proof or physical memory loading is demonstrated. E18twoConv-core architecture and symmetric zero-point0/INT8M boundary are unchanged.
