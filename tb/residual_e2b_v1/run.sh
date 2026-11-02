#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/residual_rtl build/residual_rtl build/residual_post
trap 'for log in results/residual_rtl/*.log; do [ ! -f "$log" ] || tail -n 20 "$log"; done' ERR
ulimit -c 0
python -m tools.residual_vectors --export > results/residual_rtl/export.json
python -m tools.residual_vectors > results/residual_rtl/vector_validation.json
python -m tools.make_residual_rne_vectors
verilator --version > results/residual_rtl/toolchain.txt
verilator --lint-only -Wall --top-module residual_block rtl/residual_e2b_v1/rne_clip.sv rtl/residual_e2b_v1/residual_block.sv > results/residual_rtl/lint.log 2>&1
verilator --binary --timing -j 2 --top-module tb_rne --Mdir build/residual_post \
  rtl/residual_e2b_v1/rne_clip.sv tb/residual_e2b_v1/tb_rne.sv > results/residual_rtl/build_post.log 2>&1
build/residual_post/Vtb_rne > results/residual_rtl/rne.log 2>&1
grep -q 'RNE_PASS vectors=2000' results/residual_rtl/rne.log
verilator --binary --timing --trace --trace-depth 2 -j 2 --top-module tb_residual --Mdir build/residual_rtl \
  rtl/residual_e2b_v1/rne_clip.sv rtl/residual_e2b_v1/residual_block.sv tb/residual_e2b_v1/tb_residual.sv > results/residual_rtl/build.log 2>&1
for mode in 0 1 2 5 10; do
  extra=()
  if [ "$mode" = 0 ]; then extra=(+DUMP=results/residual_rtl/normal_boundaries.csv); fi
  build/residual_rtl/Vtb_residual +MODE=$mode "${extra[@]}" > results/residual_rtl/mode$mode.log 2>&1
  if [ "$mode" = 10 ]; then grep -q OVERFLOW_PASS results/residual_rtl/mode$mode.log;
  else grep -q "CASE_PASS mode=$mode" results/residual_rtl/mode$mode.log; fi
done
for mode in 6 7 8 9; do
  if build/residual_rtl/Vtb_residual +MODE=$mode > results/residual_rtl/mode$mode.log 2>&1; then
    echo "ERROR: deliberately wrong Golden accepted, mode $mode";exit 1
  fi
  case "$mode" in
    6) marker=ACC1_MISMATCH;; 7) marker=M_MISMATCH;; 8) marker=Y_MISMATCH;; 9) marker=ADD_WIDE_MISMATCH;;
  esac
  grep -q "$marker" results/residual_rtl/mode$mode.log
done
build/residual_rtl/Vtb_residual +MODE=11 +TRACE=1 > results/residual_rtl/trace.log 2>&1
grep -q 'TRACE_WINDOW_ONLY cycles=500 completed_jobs=0' results/residual_rtl/trace.log
python -m tools.summarize_residual_rtl
