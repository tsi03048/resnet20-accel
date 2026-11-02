#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results
python3 build_packages.py > results/build.log
python3 test_packages.py > results/test.log
python3 record_results.py > results/report.log
cat results/build.log results/test.log
