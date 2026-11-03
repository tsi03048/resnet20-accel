# E8-I. Hold 여유 확보 — 같은 100 MHz에서 짧은 경로 다시 배선하기

[E8-H 패킷 수신부 Setup 개선](timing_margin.md) 다음 선택 확장입니다. 기본 이론·작은 Conv 실습을 마친 뒤 읽으세요. 이번에는 RTL의 계산 순서를 유지하고 구현 설정·배치를 개선했습니다. 실제 ZedBoard PS·DDR·DMA 실행과 FPS·전력은 **NOT_RUN**입니다.

## 1. 값이 너무 빨리 바뀌어도 문제가 되나요?

Setup은 다음 클록 전에 새 값이 준비돼야 한다는 조건입니다. Hold는 같은 클록 edge 직후에도 입력이 잠시 안정돼 있어야 한다는 조건입니다. 데이터 경로가 너무 짧고 목적지 클록이 늦게 도착하면 Hold에 불리할 수 있습니다. 클록 주기를 늘리는 방법만으로 같은 edge의 Hold 문제가 해결되지는 않습니다.

E8-H의100 MHz 배선은 Setup+0.927 ns, Hold+0.007 ns로 통과했지만 Hold 여유가 작았습니다. [이전 Hold 경로](../results/ps_dma_timing_system/reports/post_route_worst_hold.rpt)는 AMD DMA IP 내부의 수신 byte 개수→길이 레지스터였습니다. 한 LUT를 지나는 데이터 지연0.365 ns와 클록 도착 차이·레지스터 Hold 요구를 함께 계산한 결과입니다. MAC 연산식이나 INT8 반올림을 바꿀 이유가 없었습니다.

## 2. 추가 목표 0.100 ns는 무엇인가요?

구현 단계에서 `clk_fpga_0`의 Hold 검사에 사용자 uncertainty **0.100 ns**를 추가했습니다. 이는 측정한 지터 값이 아니라 **배선에 남기려는 추가 여유 목표**입니다. 클록은10 ns=100 MHz 그대로이며 기본 지터 계산도 유지합니다. [AMD set_clock_uncertainty 설명](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/set_clock_uncertainty)에 따라 Hold 검사에만 적용합니다.

```tcl
set_clock_uncertainty -hold 0.100 [get_clocks clk_fpga_0]
```

이 설정은 검사를 더 엄격하게 합니다. 배치 전 hook에서 적용하고, 배선 후에도 `ExploreWithAggressiveHoldFix` 물리 최적화를 켰습니다. 도구가 짧은 경로의 지연과 배치를 조정합니다. [AMD 물리 최적화 명령 설명](https://docs.amd.com/r/2024.2-English/ug835-vivado-tcl-commands/phys_opt_design)을 참고하세요. RTL·R202 ABI·PS 프로그램·정수 상수·계산 클록은 동일합니다.

## 3. 두 Hold 보고서를 섞지 않기

같은 최종 배선을 두 조건으로 분석했습니다. `post_route`는 추가 목표0.100 ns가 적용된 구현 보고서, `post_route_nominal`은 이전과 비교하기 위해 사용자 Hold uncertainty를0으로 놓은 보고서입니다. 제공된 최종 DCP에는 다시0.100 ns를 적용해 저장했습니다.

| 항목 | 이전 E8-H | 이번 E8-I |
| --- | ---: | ---: |
| FCLK | 100 MHz | 100 MHz |
| Setup WNS | +0.927 ns | **+0.972 ns** |
| 기존 조건 Hold WHS | +0.007 ns | **+0.119 ns** |
| 추가0.100 ns 목표 적용 후 Hold WHS | 미적용 | **+0.019 ns** |
| TNS / THS | 0 / 0 ns | 0 / 0 ns |
| LUT / 53,200 | 4,425 | 4,543 |
| FF / 106,400 | 5,655 | 5,655 |
| BRAM36 환산 / 140 | 87.5 | 87.5 |
| DSP / 220 | 0 | 0 |

기존 조건으로 비교한 Hold 여유는 **0.112 ns 증가**했습니다. 새 보고서의0.019와0.119는 서로 다른 회로가 아니라 같은 회로의 검사 예산 차이입니다. `0.119−0.100=0.019`로 확인합니다. Setup은 Hold 예산을 바꿔도+0.972 ns로 같습니다. XDC에는0.100 다음0.000처럼 순차 대입 이력이 남을 수 있으므로 마지막으로 적용되는 값과 실제 timing 보고서를 함께 확인합니다.

Vivado2025.1, XC7Z020-1CLG484, Avnet ZedBoard RevD, PS7·DDR·GP0·HP0·AXI DMA 전체 시스템 결과입니다. 두 조건 모두 시간 제약 검사12종0, 배선9,492/9,492·배선 오류0, DRC Error/Critical Warning0입니다. 생성 IP Warning16·Advisory4는 보존했습니다. hook이 `utils_1`에 등록되지 않았다는 실행 경고도 로그에 남아 있으며, 실행 스크립트는 hook을 별도로 복사·해시 검증하고 source snapshot에 포함합니다.

Setup·Hold가 이번 배선에서 통과했다는 결과입니다. 여러 배치 seed의 안정성, 더 높은 주파수, 실제 보드 전기적 동작을 보장하지 않습니다. [전체 보고서·실행 로그·소스](../results/ps_dma_hold_system/), [수집 JSON](../results/ps_dma_hold_system_actual.json), [전후 경로·예산·자원 비교](../results/ps_dma_hold_route_comparison.json)를 읽으세요.

## 4. 기능은 다시 어떻게 확인했나요?

[전체 RTL 재실행](https://github.com/tsi03048/resnet20-accel/actions/runs/41576469994)은 E8-H와 같은 RTL로 정상0→1→0, Stall, 11곳 Reset 취소 후 sample1 회복을 검사합니다. 완료5회마다61경계·최종 점수10개·예측이 일치하며, 경계 원소2,760,420개 불일치0입니다. 내려받은 sample0 CSV274,506행을 Python Golden과 다시 비교하고, 기능 시험·Vivado의 활성 RTL10개 해시를 대조합니다. 실제 사진은 Test0/1 두 종류이며 10,000장 RTL 정확도 검사는 아닙니다.

잘못된 패킷8종, 고의 Golden 변경4종, INT32 overflow, AXI-Lite 도착 순서·byte strobe·응답 hold도 검사합니다. 별도 Xsim은 byte별 Reset4회, soft Reset 동시 수신, Weight−128 오류 후67,087words의 완전 패킷 drain과 입력3,072bytes 재적재를 재실행했습니다. [전체 회귀](../results/ps_dma_hold_rtl_actual.json), [추가 Reset](../results/ps_dma_hold_reset_actual.json).

정상 계산은 **64,063,653클록/회**, MM2S279,844bytes·S2MM64bytes로 이전과 같습니다. RTL 시뮬레이션은 정수·제어 기능 검증이고, 이번 배치의 전기적 시간 조건은 Vivado 정적 타이밍으로 별도 검사합니다. RTL PASS를 배선 후 timing 시뮬레이션이나 실물 실행으로 표시하지 않습니다.

보고서 검사기 시험을 추가해 Python **60개 검사**를 통과했습니다. Hold 예산을0으로 놓고 추가 여유를 적용했다고 표시하는 경우, 두 보고서 사이에 Setup이나 false path를 바꾸는 경우, 다른 클록에만0을 적용하는 경우는 거부합니다. XSA에 포함된 bit와 제공된 bit의 바이트도 대조했습니다. 최종 DCP를 Vivado에서 실제로 다시 열어100 MHz·저장된 추가0.100 ns·Setup/Hold가 그대로인지 확인했습니다. [DCP 재열기 결과](../results/ps_dma_hold_checkpoint_actual.json).

## 5. 처음 따라 하는 순서

먼저 Python3으로 제공된 증거·파일 해시를 확인합니다. 이 명령은 보드나 시뮬레이터를 새로 실행하지 않습니다.

```powershell
python -m tools.check_hold_delivery
```

그다음 이전/새 Hold 보고서의 첫 경로를 읽고 Source·Destination·Data Path Delay·Clock Path Skew·Slack을 비교합니다. 기존 조건과 추가 목표 조건을 표의 별도 열에 기록하세요.

Windows Vivado2025.1에서 전체 회로를 새로 구현합니다. 설치 기본값은 `C:/Xilinx/2025.1/Vivado/bin/vivado.bat`이며 다른 위치는 `-VivadoPath`를 지정합니다. 스크립트는 영문 임시 경로에 소스를 복사·해시 검증하고 새 실행 폴더를 표시합니다.

```powershell
& ./board/zedboard/ps_dma_hold/run_system.ps1
python -m tools.summarize_hold_system --run build/zedboard_ps_hold_runs/표시된_실행폴더
python -m tools.compare_hold_system
```

제공할 DCP를 실제로 다시 열어 검사하려면 다음을 실행합니다. 이 시험은 제약이나 회로를 수정하지 않습니다.

```powershell
& ./board/zedboard/ps_dma_hold/run_checkpoint_check.ps1 -RunDirectory build/zedboard_ps_hold_runs/표시된_실행폴더
python -m tools.summarize_hold_checkpoint --run build/hold_checkpoint_checks/표시된_검사폴더
```

증거 수집 전에 임시 stage 폴더를 지우지 마세요. 수집기가 구현 상세 로그와 hook 적용 기록을 함께 보관합니다. 단순히 bit 생성 종료만 보고 통과로 기록하지 말고 두 예산의 Setup/Hold·자원·제약 누락·배선·경고를 확인하세요. 본인 재배선 수치는 배포 기록과 다를 수 있습니다.

별도 byte Reset 시험은 기존 R202 실행기를 그대로 사용하고 새 결과 수집기로 보관합니다.

```powershell
& ./board/zedboard/ps_dma_timing/run_packed_reset.ps1
python -m tools.summarize_hold_reset --run build/timing_reset_runs/표시된_실행폴더
```

Linux/WSL의 Python+NumPy·Verilator·C++·make 환경에서 같은 정수 RTL을 재실행합니다. GPU·재학습·CIFAR 원본 다운로드는 불필요합니다.

```bash
bash tb/ps_dma_timing/run.sh
```

이 명령은 원래 `results/ps_dma_timing_rtl/`에 결과를 만듭니다. 배포된 E8-I 재실행 증거는 `results/ps_dma_hold_rtl/`에 따로 보관해 E8-H 이력을 덮어쓰지 않았습니다. 제공된 증거를 읽은 것·본인 실행·실물 실행을 나누어 기록하세요.

## 6. 실습 묶음과 실물 준비

ZIP의 `시작.txt`에서 시작합니다. `platform_hold/output/`에는 이번 bit·XSA·DCP·PS 초기화 파일, `build/ps_dma_packed_software/`에는 호환 R202 ARM ELF, `reference/ps_dma_packed/`에는 패킷6개가 있습니다. `PACKAGE_MANIFEST.json`에서 모든 파일의 크기와 SHA256을 확인합니다. 현재 ELF·패킷은 이전과 같고 bit·XSA·DCP는 이번 배선 결과입니다.

보드가 준비된 뒤 E8-F의 revision·전원·JTAG 부팅·캐시 조건을 확인하고 이번 플랫폼을 지정합니다. 아래 명령은 PS Reset·회로 적재·ARM 실행을 수행하며 현재 실물에서는 실행하지 않았습니다.

```powershell
& ./board/zedboard/ps_dma_packed/run_board.ps1 -RunDirectory ./platform_hold -Python python
```

학생 제출에는 ① Setup과 Hold의 차이 ②0.019와0.119가 다른 이유 ③ LUT 증가와 Hold 개선의 관계 ④61경계·Stall·Reset·오류 시험 결과 ⑤ source/bit/ELF/패킷 해시를 남기세요. 기본 작은 Conv 과제와 이 선택 확장은 별도로 평가합니다. 라이선스는 팀 합의 전 보류(후보 MIT)입니다.
