#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/stem_residual_rtl build/stem_residual_rtl
trap 'for log in results/stem_residual_rtl/*.log; do [ ! -f "$log" ] || tail -n 16 "$log"; done' ERR
ulimit -c 0
python -m tools.chain_vectors --export > results/stem_residual_rtl/export.json
python -m tools.chain_vectors > results/stem_residual_rtl/vector_validation.json
verilator --version > results/stem_residual_rtl/toolchain.txt
sources=(rtl/stem_e2b_v1/requant_rne_relu.sv rtl/stem_e2b_v1/stem_conv.sv rtl/residual_e2b_v1/rne_clip.sv rtl/residual_e2b_v1/residual_block.sv rtl/stem_residual_e2b_v1/stem_residual.sv)
verilator --lint-only -Wall --timescale-override 1ns/1ps --top-module stem_residual "${sources[@]}" > results/stem_residual_rtl/lint.log 2>&1
verilator --binary --timing --trace --trace-depth 3 --timescale-override 1ns/1ps -j 2 --top-module tb_chain --Mdir build/stem_residual_rtl \
  "${sources[@]}" tb/stem_residual_e2b_v1/tb_chain.sv > results/stem_residual_rtl/build.log 2>&1
for mode in 0 1 2 5 10 11; do
  extra=()
  if [ "$mode" = 0 ]; then extra=(+DUMP=results/stem_residual_rtl/normal_boundaries.csv); fi
  build/stem_residual_rtl/Vtb_chain +MODE=$mode "${extra[@]}" > results/stem_residual_rtl/mode$mode.log 2>&1
  if [ "$mode" -ge 10 ]; then grep -q FAULT_CLEAR_PASS results/stem_residual_rtl/mode$mode.log;
  else grep -q "CASE_PASS mode=$mode" results/stem_residual_rtl/mode$mode.log; fi
done
for mode in 6 7 8 9; do
  if build/stem_residual_rtl/Vtb_chain +MODE=$mode > results/stem_residual_rtl/mode$mode.log 2>&1; then
    echo "ERROR: deliberately wrong Golden accepted, mode $mode";exit 1
  fi
  case "$mode" in
    6) marker=BRIDGE_CODE_MISMATCH;; 7) marker=M_CODE_MISMATCH;; 8) marker=Y_CODE_MISMATCH;; 9) marker=ADD_WIDE_MISMATCH;;
  esac
  grep -q "$marker" results/stem_residual_rtl/mode$mode.log
done
build/stem_residual_rtl/Vtb_chain +MODE=15 +TRACE=1 > results/stem_residual_rtl/trace.log 2>&1
grep -q 'TRACE_WINDOW_ONLY cycles=500 completed_jobs=0' results/stem_residual_rtl/trace.log
python -m tools.summarize_chain_rtl
