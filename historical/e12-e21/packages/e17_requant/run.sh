#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results
python3 reference/make_vectors.py > results/reference.log
TASK_VERILATOR="${VERILATOR:-verilator}"
"$TASK_VERILATOR" --lint-only --top-module requant_join -Wall rtl/*.sv > results/lint.log 2>&1
"$TASK_VERILATOR" --cc --main --exe --timing --trace --top-module tb_requant -CFLAGS -std=c++20 --Mdir sim/obj_dir rtl/*.sv sim/tb_requant.sv > results/elaboration.log 2>&1
make -C sim/obj_dir -f Vtb_requant.mk CFG_CXXFLAGS_PCH_I=-include -j2 > results/build.log 2>&1
./sim/obj_dir/Vtb_requant > results/simulation.log 2>&1
./sim/obj_dir/Vtb_requant +TRACE > results/trace_window.log 2>&1
python3 verify_reference_errors.py > results/negative_report.log
python3 record_results.py > results/report.log
cat results/reference.log results/simulation.log
