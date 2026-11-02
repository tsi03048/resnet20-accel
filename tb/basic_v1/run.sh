#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p results/basic_rtl
iverilog -V > results/basic_rtl/toolchain.txt 2>&1
iverilog -g2012 -s tb_conv_toy -o results/basic_rtl/toy rtl/basic_v1/conv_toy.sv tb/basic_v1/tb_conv_toy.sv
for mode in 0 1 2; do
  vvp results/basic_rtl/toy +MODE=$mode > results/basic_rtl/mode$mode.log 2>&1
  grep -q "PASS mode=$mode" results/basic_rtl/mode$mode.log
  mv toy.vcd results/basic_rtl/mode$mode.vcd
done
if vvp results/basic_rtl/toy +MODE=3 > results/basic_rtl/mode3.log 2>&1; then
  echo 'ERROR: wrong expected value was not rejected'; exit 1
fi
grep -q EXPECTED_MISMATCH results/basic_rtl/mode3.log
mv toy.vcd results/basic_rtl/mode3.vcd
echo 'PASS: normal, stall, reset; deliberate mismatch rejected'
iverilog -g2012 -s tb_board_wrapper -o results/basic_rtl/board_wrapper rtl/basic_v1/conv_toy.sv board/zedboard/basic_vio_top.sv tb/basic_v1/tb_board_wrapper.sv
vvp results/basic_rtl/board_wrapper > results/basic_rtl/board_wrapper.log 2>&1
grep -q 'PASS board wrapper' results/basic_rtl/board_wrapper.log
