#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results sim/obj_dir
python3 reference/make_vectors.py > results/reference.log
E12_VERILATOR="${VERILATOR:-verilator}"
"$E12_VERILATOR" --lint-only --top-module conv_fixed_top -Wall \
  rtl/conv_fixed_top.sv rtl/read_hold.sv rtl/mac_scalar.sv rtl/postprocess4.sv \
  > results/lint.log 2>&1
"$E12_VERILATOR" --cc --main --exe --timing --trace --top-module tb_conv_fixed \
  -CFLAGS -std=c++20 --Mdir sim/obj_dir \
  rtl/conv_fixed_top.sv rtl/read_hold.sv rtl/mac_scalar.sv rtl/postprocess4.sv sim/tb_conv_fixed.sv \
  > results/elaboration.log 2>&1
make -C sim/obj_dir -f Vtb_conv_fixed.mk CFG_CXXFLAGS_PCH_I=-include -j2 > results/build.log 2>&1
./sim/obj_dir/Vtb_conv_fixed +TRACE > results/simulation.log 2>&1
cat results/reference.log results/simulation.log
