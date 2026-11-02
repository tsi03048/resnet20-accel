#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/full_fpga_v2_rtl build
trap 'for log in results/full_fpga_v2_rtl/*.log; do [ ! -f "$log" ] || tail -n 12 "$log"; done' ERR
ulimit -c 0
phase=${1:-all}
if [[ "$phase" == build || "$phase" == all ]]; then
  python -m tools.full_vectors --export > results/full_fpga_v2_rtl/export.json
  python -m tools.full_vectors > results/full_fpga_v2_rtl/vector_validation.json
  python -m tools.make_full_post_vectors > /dev/null
  python -m tools.v2_mul_vectors
  verilator --version > results/full_fpga_v2_rtl/toolchain.txt
  files=(rtl/full_e2b_v1/argmax10.sv rtl/full_e2b_fpga_v2/feature_ram.sv rtl/full_e2b_fpga_v2/sync_bram.sv rtl/full_e2b_fpga_v2/weight_bram.sv rtl/full_e2b_fpga_v2/mul_serial.sv rtl/full_e2b_fpga_v2/rne_serial.sv rtl/full_e2b_fpga_v2/full_model.sv)
  verilator --lint-only -Wall -Irtl/full_e2b_fpga_v2 --top-module full_model "${files[@]}" > results/full_fpga_v2_rtl/lint.log 2>&1
  verilator --binary --timing -Irtl/full_e2b_fpga_v2 -j 2 --top-module tb_full --Mdir build/full_fpga_v2_model "${files[@]}" tb/full_e2b_fpga_v2/tb_full.sv > results/full_fpga_v2_rtl/build.log 2>&1
  for unit in post mul; do
    verilator --binary --timing -j 2 --top-module tb_$unit --Mdir build/full_v2_$unit rtl/full_e2b_fpga_v2/rne_serial.sv rtl/full_e2b_fpga_v2/mul_serial.sv tb/full_e2b_fpga_v2/tb_$unit.sv > results/full_fpga_v2_rtl/build_$unit.log 2>&1
    build/full_v2_$unit/Vtb_$unit > results/full_fpga_v2_rtl/$unit.log 2>&1
    grep -q "${unit^^}_PASS" results/full_fpga_v2_rtl/$unit.log
  done
  verilator --binary --timing -j 2 --top-module tb_argmax --Mdir build/full_v2_argmax rtl/full_e2b_v1/argmax10.sv tb/full_e2b_v1/tb_argmax.sv > results/full_fpga_v2_rtl/build_argmax.log 2>&1
  build/full_v2_argmax/Vtb_argmax > results/full_fpga_v2_rtl/argmax.log 2>&1
  grep -q ARGMAX_PASS results/full_fpga_v2_rtl/argmax.log
fi
if [[ "$phase" == case || "$phase" == all ]]; then
  python -m tools.full_vectors --export > /dev/null
  python -m tools.full_vectors > /dev/null
  selected=${2:-all}
  for mode in 0 1 2 6 7 8 9 10 11; do
    if [[ "$selected" != all && "$selected" != "$mode" && !( "$selected" == negative && "$mode" -ge 6 ) ]]; then continue;fi
    extra=();if [[ "$mode" == 0 ]]; then extra=(+DUMP=results/full_fpga_v2_rtl/normal_boundaries.csv);fi
    if [[ "$mode" -ge 6 && "$mode" -le 9 ]]; then
      if build/full_fpga_v2_model/Vtb_full +MODE=$mode > results/full_fpga_v2_rtl/mode$mode.log 2>&1; then echo "Wrong Golden accepted mode=$mode";exit 1;fi
      case "$mode" in 6|9) marker=CODE_MISMATCH;;7) marker=SKIP_MISMATCH;;8) marker=ACC_MISMATCH;;esac
      grep -q "$marker" results/full_fpga_v2_rtl/mode$mode.log
    else
      build/full_fpga_v2_model/Vtb_full +MODE=$mode "${extra[@]}" > results/full_fpga_v2_rtl/mode$mode.log 2>&1 || { tail -n 20 results/full_fpga_v2_rtl/mode$mode.log;exit 1; }
      case "$mode" in 10) marker=LOADER_PASS;;11) marker=OVERFLOW_PASS;;*) marker="CASE_PASS mode=$mode";;esac
      grep -q "$marker" results/full_fpga_v2_rtl/mode$mode.log
    fi
    tail -n 3 results/full_fpga_v2_rtl/mode$mode.log
  done
fi
if [[ "$phase" == summary || "$phase" == all ]]; then python -m tools.summarize_v2_rtl;fi
