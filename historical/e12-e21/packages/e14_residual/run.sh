#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results
python3 reference/make_vectors.py > results/reference.log
TASK_VERILATOR="${VERILATOR:-verilator}"
for full in 0 1; do
  if [ "$full" = 0 ]; then channels=2; height=4; else channels=16; height=32; fi
  build_dir="sim/obj_$full"
  mkdir -p "$build_dir"
  "$TASK_VERILATOR" --lint-only --top-module residual_block -Wall \
    -GC="$channels" -GH="$height" rtl/*.sv > "results/lint_$full.log" 2>&1
  "$TASK_VERILATOR" --cc --main --exe --timing --trace --top-module tb_residual \
    -GFULL="$full" -CFLAGS -std=c++20 --Mdir "$build_dir" \
    rtl/*.sv sim/tb_residual.sv > "results/elaboration_$full.log" 2>&1
  make -C "$build_dir" -f Vtb_residual.mk CFG_CXXFLAGS_PCH_I=-include -j2 > "results/build_$full.log" 2>&1
  "./$build_dir/Vtb_residual" > "results/simulation_$full.log" 2>&1
done
./sim/obj_0/Vtb_residual +TRACE > results/trace_window.log 2>&1
python3 verify_missing_reference.py sim/obj_1/Vtb_residual reference/full/job0/input.hex > results/negative_test_report.log
python3 record_results.py > results/report.log
cat results/reference.log results/simulation_0.log results/simulation_1.log
