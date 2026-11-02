#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results
python3 reference/make_vectors.py > results/reference.log
TASK_VERILATOR="${VERILATOR:-verilator}"
for tiny in 0 1; do
  build_dir="sim/obj_$tiny"
  mkdir -p "$build_dir"
  "$TASK_VERILATOR" --lint-only --top-module conv3x3_core -Wall \
    -GCIN=$([ "$tiny" = 1 ] && echo 2 || echo 3) -GCOUT=$([ "$tiny" = 1 ] && echo 2 || echo 16) \
    -GH=$([ "$tiny" = 1 ] && echo 4 || echo 32) -GW=$([ "$tiny" = 1 ] && echo 4 || echo 32) \
    -GPAD=$([ "$tiny" = 1 ] && echo 0 || echo 1) rtl/*.sv > "results/lint_$tiny.log" 2>&1
  "$TASK_VERILATOR" --cc --main --exe --timing --trace --top-module tb_stem \
    -GTINY="$tiny" -CFLAGS -std=c++20 --Mdir "$build_dir" \
    rtl/*.sv sim/tb_stem.sv > "results/elaboration_$tiny.log" 2>&1
  make -C "$build_dir" -f Vtb_stem.mk CFG_CXXFLAGS_PCH_I=-include -j2 > "results/build_$tiny.log" 2>&1
  "./$build_dir/Vtb_stem" > "results/simulation_$tiny.log" 2>&1
done
./sim/obj_0/Vtb_stem +TRACE > results/trace_window.log 2>&1
python3 verify_missing_reference.py sim/obj_1/Vtb_stem reference/tiny/job0/input.hex > results/negative_test_report.log
python3 record_results.py > results/report.log
cat results/reference.log results/simulation_0.log results/simulation_1.log
