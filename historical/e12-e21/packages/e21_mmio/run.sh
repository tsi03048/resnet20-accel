#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
TASK_VERILATOR="${VERILATOR:-verilator}"
mkdir -p results
for cfg in 0 1; do
 if [ "$cfg" = 0 ]; then channels=2; height=4; else channels=16; height=32; fi
 "$TASK_VERILATOR" --lint-only -Wall --top-module mmio_transition -GC="$channels" -GH="$height" rtl/*.sv > "results/lint_$cfg.log" 2>&1
 "$TASK_VERILATOR" --cc --main --exe --timing --top-module tb_mmio -GFULL="$cfg" -CFLAGS -std=c++20 --Mdir "sim/obj_$cfg" rtl/*.sv sim/tb_mmio.sv > "results/elaboration_$cfg.log" 2>&1
 make -C "sim/obj_$cfg" -f Vtb_mmio.mk CFG_CXXFLAGS_PCH_I=-include -j2 > "results/build_$cfg.log" 2>&1
 "./sim/obj_$cfg/Vtb_mmio" > "results/simulation_$cfg.log" 2>&1
done
cat results/simulation_0.log results/simulation_1.log
