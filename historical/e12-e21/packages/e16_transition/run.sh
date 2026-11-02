#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results
python3 reference/make_vectors.py > results/reference.log
TASK_VERILATOR="${VERILATOR:-verilator}"
for cfg in 0 1 2; do
  if [ "$cfg" = 0 ]; then channels=2; height=4; elif [ "$cfg" = 1 ]; then channels=16; height=32; else channels=32; height=16; fi
  build_dir="sim/obj_$cfg"
  "$TASK_VERILATOR" --lint-only --top-module transition_block -Wall -GC="$channels" -GH="$height" rtl/*.sv > "results/lint_$cfg.log" 2>&1
  "$TASK_VERILATOR" --cc --main --exe --timing --trace --top-module tb_transition -GFULL="$cfg" -CFLAGS -std=c++20 --Mdir "$build_dir" rtl/*.sv sim/tb_transition.sv > "results/elaboration_$cfg.log" 2>&1
  make -C "$build_dir" -f Vtb_transition.mk CFG_CXXFLAGS_PCH_I=-include -j2 > "results/build_$cfg.log" 2>&1
  "./$build_dir/Vtb_transition" > "results/simulation_$cfg.log" 2>&1
done
./sim/obj_0/Vtb_transition +TRACE > results/trace_window.log 2>&1
python3 verify_missing_reference.py sim/obj_1/Vtb_transition reference/stage12/job0/input.hex > results/negative_report.log
python3 record_results.py > results/report.log
cat results/reference.log results/simulation_0.log results/simulation_1.log results/simulation_2.log
