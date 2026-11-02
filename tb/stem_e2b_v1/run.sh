#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/stem_rtl
trap 'for log in results/stem_rtl/*.log; do [ ! -f "$log" ] || tail -n 20 "$log"; done' ERR
python -m tools.verify_stem_vectors > results/stem_rtl/vector_validation.json
python -m tools.make_stem_rne_vectors
iverilog -V > results/stem_rtl/toolchain.txt 2>&1
iverilog -g2012 -s tb_requant -o results/stem_rtl/post rtl/stem_e2b_v1/requant_rne_relu.sv tb/stem_e2b_v1/tb_requant.sv
vvp results/stem_rtl/post > results/stem_rtl/rne.log 2>&1
grep -q 'RNE_PASS vectors=1280' results/stem_rtl/rne.log
iverilog -g2012 -s tb_stem -o results/stem_rtl/stem rtl/stem_e2b_v1/requant_rne_relu.sv rtl/stem_e2b_v1/stem_conv.sv tb/stem_e2b_v1/tb_stem.sv
for mode in 0 1 2 5 6; do
  extra=()
  if [ "$mode" = 0 ]; then extra=(+TRACE=1 +DUMP=results/stem_rtl/normal_outputs.csv); fi
  vvp results/stem_rtl/stem +MODE=$mode "${extra[@]}" > results/stem_rtl/mode$mode.log 2>&1
  if [ "$mode" = 6 ]; then grep -q OVERFLOW_PASS results/stem_rtl/mode$mode.log;
  else grep -q "CASE_PASS mode=$mode" results/stem_rtl/mode$mode.log; fi
done
for mode in 3 4; do
  if vvp results/stem_rtl/stem +MODE=$mode > results/stem_rtl/mode$mode.log 2>&1; then
    echo "ERROR: deliberately incorrect Golden accepted, mode $mode"; exit 1
  fi
  if [ "$mode" = 3 ]; then grep -q EXPECTED_OUTPUT_MISMATCH results/stem_rtl/mode$mode.log;
  else grep -q EXPECTED_ACC_MISMATCH results/stem_rtl/mode$mode.log; fi
done
python -m tools.summarize_stem_rtl
cat results/stem_rtl/summary.json
