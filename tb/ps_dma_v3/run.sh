#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/ps_dma_pipe_rtl build
trap 'for log in results/ps_dma_pipe_rtl/*.log; do [ ! -f "$log" ] || tail -n 12 "$log"; done' ERR
ulimit -c 0
phase=${1:-all}
if [[ "$phase" == build || "$phase" == all ]]; then
  python -m tools.full_vectors --export > results/ps_dma_pipe_rtl/export.json
  python -m tools.full_vectors > results/ps_dma_pipe_rtl/vector_validation.json
  python -m tools.make_full_post_vectors > /dev/null
  python -m tools.v2_mul_vectors
  verilator --version > results/ps_dma_pipe_rtl/toolchain.txt
  files=(rtl/full_e2b_v1/argmax10.sv rtl/full_e2b_fpga_v3/feature_ram.sv rtl/full_e2b_fpga_v3/sync_bram.sv rtl/full_e2b_fpga_v3/weight_bram.sv rtl/full_e2b_fpga_v3/mul_serial.sv rtl/full_e2b_fpga_v3/rne_serial.sv rtl/full_e2b_fpga_v3/full_model.sv rtl/ps_dma_v2/resnet20_axi_packed.sv rtl/ps_dma_v2/resnet20_axi_packed_bd.v)
  verilator --lint-only -Wall -Irtl/full_e2b_fpga_v3 --top-module resnet20_axi_packed_bd "${files[@]}" > results/ps_dma_pipe_rtl/lint.log 2>&1
  verilator --binary --timing -Irtl/full_e2b_fpga_v3 -j 2 --top-module tb_ps_pipe --Mdir build/ps_dma_pipe_model "${files[@]}" tb/ps_dma_v3/tb_ps_pipe.sv > results/ps_dma_pipe_rtl/build.log 2>&1
  for unit in post mul; do
    verilator --binary --timing -j 2 --top-module tb_$unit --Mdir build/ps_dma_pipe_$unit rtl/full_e2b_fpga_v3/rne_serial.sv rtl/full_e2b_fpga_v3/mul_serial.sv tb/full_e2b_fpga_v2/tb_$unit.sv > results/ps_dma_pipe_rtl/build_$unit.log 2>&1
    build/ps_dma_pipe_$unit/Vtb_$unit > results/ps_dma_pipe_rtl/$unit.log 2>&1
    grep -q "${unit^^}_PASS" results/ps_dma_pipe_rtl/$unit.log
  done
  verilator --binary --timing -j 2 --top-module tb_argmax --Mdir build/ps_dma_pipe_argmax rtl/full_e2b_v1/argmax10.sv tb/full_e2b_v1/tb_argmax.sv > results/ps_dma_pipe_rtl/build_argmax.log 2>&1
  build/ps_dma_pipe_argmax/Vtb_argmax > results/ps_dma_pipe_rtl/argmax.log 2>&1
  grep -q ARGMAX_PASS results/ps_dma_pipe_rtl/argmax.log
fi
if [[ "$phase" == case || "$phase" == all ]]; then
  python -m tools.full_vectors --export > /dev/null
  python -m tools.full_vectors > /dev/null
  selected=${2:-all}
  for mode in 0 1 2 3 4 6 7 8 9 11; do
    if [[ "$selected" != all && "$selected" != "$mode" && !( "$selected" == negative && "$mode" -ge 6 ) ]]; then continue;fi
    extra=();if [[ "$mode" == 0 ]]; then extra=(+DUMP=results/ps_dma_pipe_rtl/normal_boundaries.csv);fi
    if [[ "$mode" -ge 6 && "$mode" -le 9 ]]; then
      if build/ps_dma_pipe_model/Vtb_ps_pipe +MODE=$mode > results/ps_dma_pipe_rtl/mode$mode.log 2>&1; then echo "Wrong Golden accepted mode=$mode";exit 1;fi
      case "$mode" in 6|9) marker=CODE_MISMATCH;;7) marker=SKIP_MISMATCH;;8) marker=ACC_MISMATCH;;esac
      grep -q "$marker" results/ps_dma_pipe_rtl/mode$mode.log
    else
      build/ps_dma_pipe_model/Vtb_ps_pipe +MODE=$mode "${extra[@]}" > results/ps_dma_pipe_rtl/mode$mode.log 2>&1 || { tail -n 20 results/ps_dma_pipe_rtl/mode$mode.log;exit 1; }
      case "$mode" in 3) marker=PROTOCOL_PASS;;4) marker=PACKED_LOADER_PASS;;11) marker=OVERFLOW_PASS;;*) marker="CASE_PASS mode=$mode";;esac
      grep -q "$marker" results/ps_dma_pipe_rtl/mode$mode.log
    fi
    tail -n 3 results/ps_dma_pipe_rtl/mode$mode.log
  done
fi
if [[ "$phase" == summary || "$phase" == all ]]; then python -m tools.summarize_pipe_rtl;fi
