#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/transition_rtl
trap 'for log in results/transition_rtl/stage*/*.log; do [ ! -f "$log" ] || tail -n 16 "$log"; done' ERR
ulimit -c 0
python -m tools.transition_vectors --export > results/transition_rtl/export.json
python -m tools.transition_vectors > results/transition_rtl/vector_validation.json
verilator --version > results/transition_rtl/toolchain.txt
for stage in 2 3; do
  out=results/transition_rtl/stage$stage
  obj=build/transition_stage$stage
  mkdir -p "$out" "$obj"
  verilator --lint-only -Wall -GSTAGE=$stage --top-module transition_block \
    rtl/residual_e2b_v1/rne_clip.sv rtl/transition_e2b_v1/transition_block.sv > "$out/lint.log" 2>&1
  verilator --binary --timing --trace --trace-depth 2 -j 2 -GSTAGE=$stage --top-module tb_transition --Mdir "$obj" \
    rtl/residual_e2b_v1/rne_clip.sv rtl/transition_e2b_v1/transition_block.sv tb/transition_e2b_v1/tb_transition.sv > "$out/build.log" 2>&1
  for mode in 0 1 2 5 11; do
    extra=()
    if [ "$mode" = 0 ]; then extra=(+DUMP=$out/normal_boundaries.csv); fi
    "$obj/Vtb_transition" +MODE=$mode "${extra[@]}" > "$out/mode$mode.log" 2>&1
    if [ "$mode" = 11 ]; then grep -q OVERFLOW_PASS "$out/mode$mode.log";
    else grep -q "CASE_PASS stage=$stage mode=$mode" "$out/mode$mode.log"; fi
  done
  for mode in 6 7 8 9 10 12 13; do
    if "$obj/Vtb_transition" +MODE=$mode > "$out/mode$mode.log" 2>&1; then
      echo "ERROR: wrong Golden accepted: stage=$stage mode=$mode";exit 1
    fi
    case "$mode" in
      6) marker=ACC1_MISMATCH;; 7) marker=M_MISMATCH;; 8|12) marker=SKIP_PAIR_MISMATCH;;
      9) marker=Y_MISMATCH;; 10) marker=ADD_WIDE_MISMATCH;; 13) marker=OPTION_A_READ_ADDRESS;;
    esac
    grep -q "$marker" "$out/mode$mode.log"
  done
  for kind in 1 2; do
    "$obj/Vtb_transition" +MODE=15 +TRACE=$kind > "$out/trace$kind.log" 2>&1
    grep -q "TRACE_WINDOW_ONLY kind=$kind cycles=500 completed_jobs=0" "$out/trace$kind.log"
  done
done
python -m tools.summarize_transition_rtl
