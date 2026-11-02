#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/full_rtl build
trap 'for log in results/full_rtl/*.log; do [ ! -f "$log" ] || tail -n 12 "$log"; done' ERR
ulimit -c 0
phase=${1:-all}
if [[ "$phase" == build || "$phase" == all ]]; then
  python -m tools.full_vectors --export > results/full_rtl/export.json
  python -m tools.full_vectors > results/full_rtl/vector_validation.json
  python -m tools.make_full_post_vectors > results/full_rtl/post_vectors.txt
  verilator --version > results/full_rtl/toolchain.txt
  files=(rtl/full_e2b_v1/requant_full.sv rtl/full_e2b_v1/argmax10.sv rtl/full_e2b_v1/full_model.sv)
  verilator --lint-only -Wall -Irtl/full_e2b_v1 --top-module full_model "${files[@]}" > results/full_rtl/lint.log 2>&1
  verilator --binary --timing -Irtl/full_e2b_v1 -j 2 --top-module tb_full --Mdir build/full_model "${files[@]}" tb/full_e2b_v1/tb_full.sv > results/full_rtl/build.log 2>&1
  for unit in post argmax; do
    verilator --binary --timing -j 2 --top-module tb_$unit --Mdir build/full_$unit "${files[@]:0:2}" tb/full_e2b_v1/tb_$unit.sv > results/full_rtl/build_$unit.log 2>&1
    build/full_$unit/Vtb_$unit > results/full_rtl/$unit.log 2>&1
    grep -q "${unit^^}_PASS" results/full_rtl/$unit.log
  done
fi
if [[ "$phase" == case || "$phase" == all ]]; then
  python -m tools.full_vectors --export > /dev/null
  python -m tools.full_vectors > /dev/null
  selected=${2:-all}
  for mode in 0 1 2 6 7 8 9 10 11; do
    if [[ "$selected" != all && "$selected" != "$mode" && !( "$selected" == negative && "$mode" -ge 6 ) ]]; then continue;fi
    extra=();if [[ "$mode" == 0 ]]; then extra=(+DUMP=results/full_rtl/normal_boundaries.csv);fi
    if [[ "$mode" -ge 6 && "$mode" -le 9 ]]; then
      if build/full_model/Vtb_full +MODE=$mode > results/full_rtl/mode$mode.log 2>&1; then echo "Wrong Golden accepted mode=$mode";exit 1;fi
      case "$mode" in 6|9) marker=CODE_MISMATCH;;7) marker=SKIP_MISMATCH;;8) marker=ACC_MISMATCH;;esac
      grep -q "$marker" results/full_rtl/mode$mode.log
    else
      build/full_model/Vtb_full +MODE=$mode "${extra[@]}" > results/full_rtl/mode$mode.log 2>&1 || { tail -n 20 results/full_rtl/mode$mode.log;exit 1; }
      case "$mode" in 10) marker=LOADER_PASS;;11) marker=OVERFLOW_PASS;;*) marker="CASE_PASS mode=$mode";;esac
      grep -q "$marker" results/full_rtl/mode$mode.log
    fi
    tail -n 3 results/full_rtl/mode$mode.log
  done
fi
if [[ "$phase" == summary || "$phase" == all ]]; then python -m tools.summarize_full_rtl;fi
