# E19 · Diagnostic constant package and preflight validation

This is a Python software packaging/validation step, not a new RTL test or a trained checkpoint exporter. Four packages are derived from hash-checked E18 source vectors:small/job1 compatibility,small/job4 varied,stage12/job1 varied,stage23/job1 varied. Original snapshots in source_e18/ are audit material; its original make_vectors.py is not the E19 entry point.

## Reproduce fixture build/tests

```bash
bash run.sh
```

Python3 standard library only. Builds manifests/constants, recreates the fixture expected_manifests.json, validates4packages/44constant files, emits4software preloads and runs30negative rejection cases. Logs are results/build.log,test.log,validation.json. Rebuilding expected_manifests.json is intentional fixture regeneration, NOT establishment of an independent production trust anchor.

## Validate a released package without rebuilding it

```bash
python3 validate_package.py packages/small_varied
python3 validate_package.py packages/small_varied TRUSTED_MANIFEST_SHA256
python3 prepare_preload.py packages/small_varied preloads/reviewed.json TRUSTED_MANIFEST_SHA256
```

Replace TRUSTED_MANIFEST_SHA256 with the actual64lowercase hex digest retained independently for the approved release. Optional-pin validation checks internal consistency only; prepare_preload requires a pin. Included fixture pins are not signatures or protection against someone editing both packages and pins.

## Explicit contract

Schema1,target e18_transition_diag_v1; diagnostic provenance, fixed shapes Cin/H=(2,4),(16,32),(32,16),Cout=2Cin,Conv1stride2/Conv2stride1/PAD1. All activation zero points0; RNE ties-even; Conv1 requant/ReLU/sat8; Conv2 requant/sat8 storedM; Add INT8M+OptionA with wide sum/oneRNE/ReLU/sat8; whole tables captured at blockcommand.

Eleven roles:weight1/2,bias1/2,n1/n2/nm/ns,s1/s2/sa. Weight OIHW and all coefficients/bias output-channel axis0. Text hex is logical row-major; not packed native-endian binary. Weight signed8 stored as2hex chars/element; bias signed32 as8chars; N unsigned16 and shift unsigned5 carried in32bit text words(8chars), with explicit logical-range checks. Count,shape,layout,dtype,storagebits,actual byte length,SHA256 and canonical relative path are checked. Reject missing/symlink files, duplicate paths/JSONkeys, unsupported targets/versions/contracts and unsafe bias bounds. Unknown unused physical files are not loaded.

Conservative accumulator condition per output channel: bias +/- 128*sum(abs(weight)) must lie within signed32. This covers all signed8 inputs and every prefix via a deliberately conservative bound, including padding0. It can reject a case that is safe only under tighter activation assumptions; it is not a theorem about arbitrary model preprocessing or unseen RTL.

## Preload snapshot

Manifest is read once, pinned digest and parsed metadata use the same bytes. Each constant is read once and the same bytes are hashed/decoded. prepare_preload uses already-validated integer lists in memory rather than reopening the source hex, then atomically replaces the software JSON output. This is a software snapshot, not CPU/AXI/DMA writes, hardware memory commit or a guarantee that prepared in E18 became1.

If validation fails, prepare returns nonzero and preserves an existing output. Caller must honor exit status,source/target/manifest identity and job generation. Never treat a leftover valid snapshot from an older job as current authorization to start hardware.

## What PASS cannot prove

Internal hashes do not prove authenticity, correct checkpoint, Channel order, scale coherence, accuracy, arbitrary exporter correctness or FPGA operation. A coherent content+manifest edit without an external pin is intentionally shown to pass structural validation. A pin rejects such an edit but does not make the original release numerically correct. Validate exporter/reference outputs and actual RTL separately. The source-generator digest is recorded lineage, not independently authenticated by the schema validator.

No new model inference,RTL simulation,physical loading,FPGA synthesis/timing/board,coefficientRAM protocol,or production release-signing system was exercised. E18 simulation evidence remains separate. Supported shapes/contract are deliberately narrow; incompatible models require a new target/schema/validator and tests.
