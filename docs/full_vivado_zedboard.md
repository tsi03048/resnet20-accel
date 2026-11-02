# E8-C. 전체 RTL을 ZedBoard 대상으로 합성하고 보고서 읽기

[E8-B](full_e2b_rtl.md)에서는 실제 정수 입력 0→1→0과 Stall·Reset을 실행해 계산이 맞는지 확인했습니다. 이번에는 **그 전체 RTL을 Vivado가 어떤 회로로 바꾸는지** 확인합니다. 계산 결과의 일치, FPGA에 들어가는 크기, 정해진 시간 안에 끝나는지는 각각 확인해야 합니다.

S5의 선택 확장입니다. 처음에는 [계산 반복하기](fundamentals/D2.md) → [값 보관하기](fundamentals/D3.md) → [값 전달하기](fundamentals/D5.md)를 읽으세요. 작은 Conv의 보드 실습은 [S6](learning/S6.md)입니다.

## 1. 이번에 만드는 것

| 항목 | 이번 설정 |
| --- | --- |
| FPGA | ZedBoard XC7Z020-1CLG484, Vivado part `xc7z020clg484-1` |
| Top | `full_model`, 기본 합성 소스는 `rtl/full_e2b_fpga_v1/full_model.sv` |
| 범위 | Stem·9 Block·GAP·FC, 실제 정수 규약을 구현한 전체 코어 |
| 합성 방식 | Out-of-context(OOC), 다른 시스템에 넣기 전 코어만 분석 |
| 클록 목표 | 100 MHz, 한 주기 10 ns |
| 외부 인터페이스 가정 | 모든 데이터 입력·출력 max delay 2 ns, min delay 0 ns |
| 포함하지 않은 것 | PS·DDR·AXI/DMA·VIO·보드 핀·bitstream·보드 프로그래밍 |

OOC는 코어를 떼어 분석하는 방식입니다. 넓은 loader·trace 포트를 ZedBoard의 외부 핀에 하나씩 연결했다는 뜻이 아닙니다. 이 포트는 이후 내부 버스나 제어 회로에 연결해야 합니다. 2 ns는 코어 경계의 비교용 시간 예산이며 실제 주변 회로를 측정한 값이 아닙니다. [AMD synth_design의 OOC 설명](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/synth_design)을 참고하세요.

합성할 때 Test 사진이나 Golden을 회로 안에 넣지 않습니다. Weight도 실행 중 loader로 적재하는 메모리로 남습니다. 합성 보고서는 고정 입력 하나의 답을 미리 계산해 지운 회로의 결과가 아닙니다.

### 원래 RTL에서 무엇을 고쳤나요?

기존 `full_e2b_v1`은 계산의 기준을 검증한 버전으로 보존합니다. 실제 합성에서는 큰 다차원 feature 배열의 전개에 오래 걸렸습니다. 단일 배열로만 바꾼 비교 버전(`flat`)도 `Synth 8-3391`로 중단됐습니다. 메모리 읽기·쓰기 형태가 지원되는 RAM 패턴이 아니어서 393,216 bit를 개별 레지스터로 풀려고 했기 때문입니다. 이 숫자는 실제 합성 FF 사용량 보고서가 아닙니다.

FPGA 버전은 `feature_ram.sv`에 동기식 true dual-port RAM을 명시합니다. A 포트는 읽기/쓰기, B 포트는 읽기입니다. 주소는 `bank*16384+offset`으로 세 논리 bank를 구분합니다. 메모리 자체는 Reset으로 비우지 않고 loader의 준비 상태와 데이터 수명으로 유효성을 관리합니다.

BRAM은 읽기 주소를 주는 순간 결과가 바로 나오는 배열처럼 사용하지 않습니다. 읽기를 요청한 클록 뒤에 값을 받아 사용합니다. 그래서 Conv/GAP 읽기 뒤 `READ_LATCH`, Add의 두 입력 읽기 뒤 `ADD_LATCH`를 추가했습니다. 연산 순서·정수 상수·RNE·Golden은 유지하며, 지연이 달라진 새 소스는 전체 RTL 시험을 다시 수행합니다. 원래 버전의 통과 기록을 새 버전의 통과로 대신하지 않습니다.

## 2. 세 가지 검증을 나눠 읽기

| 단계 | 질문 | 증거 |
| --- | --- | --- |
| RTL 시뮬레이션 | 입력을 주면 같은 정수를 내는가? | E8-B의 61경계·점수·Stall·Reset |
| 합성 | HDL을 어떤 논리·메모리 자원으로 만들었는가? | post_synth 자원 보고서·체크포인트 |
| 배치·배선 | 실제 소자 위치와 연결 지연을 반영해 시간 조건을 맞추는가? | post_route 타이밍·배선 상태·제약 점검 |

시뮬레이션이 통과해도 합성이 실패하거나 자원이 넘칠 수 있습니다. 합성 후 타이밍은 추정값입니다. 배치·배선 후 보고서와 구분합니다. 보드 동작까지 확인하려면 시스템 연결과 bitstream·실물 검증이 더 필요합니다.

## 3. 자원 이름부터 이해하기

| 이름 | 쉬운 뜻 | 확인할 점 |
| --- | --- | --- |
| LUT | 작은 논리 계산·선택 기능 | 주소 계산·나눗셈·선택 회로가 커지면 증가 |
| FF / Register | 클록마다 한 bit를 기억 | 상태·중간 합·파이프라인·메모리 구현에 사용 |
| BRAM | FPGA 안의 전용 메모리 | HDL 배열이 실제 BRAM으로 추론됐는지 확인 |
| DSP | 곱셈·누산 등에 쓰는 전용 계산 자원 | Conv MAC 외의 눈금 변환 곱셈도 사용 가능 |

`Block RAM Tile`은 36 Kb 블록 기준이며 18 Kb 블록이 섞이면 0.5 단위가 나올 수 있습니다. BRAM과 DSP만 보는 것으로 충분하지 않습니다. LUT/FF도 장치 용량 이하여야 합니다. [AMD report_utilization](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/report_utilization)의 Used·Available·Util%를 함께 읽으세요.

‘순차 Conv MAC 한 개’가 ‘DSP 한 개’를 뜻하지는 않습니다. Requant의 넓은 곱, Add의 두 눈금 변환, 주소 연산 등도 회로가 됩니다. 마찬가지로 배열에 48 KiB를 예약했다는 사실만으로 BRAM 배치가 해결되지는 않습니다. 읽기 포트·쓰기 포트·동기 읽기 형태와 실제 추론 결과를 봐야 합니다.

## 4. 시간 보고서 읽기

10 ns마다 다음 값을 받아야 한다면 그 사이의 계산·배선·레지스터 시간 조건을 만족해야 합니다.

| 항목 | 읽는 방법 |
| --- | --- |
| WNS | 가장 나쁜 setup 여유 시간. 음수이면 목표 위반 |
| TNS | setup 위반 endpoint의 부족 시간을 합친 값 |
| WHS / THS | hold 여유와 위반 합계. 너무 빨리 바뀌는 경로도 검사 |
| WPWS / TPWS | 클록 pulse-width 여유와 위반 합계 |
| Worst setup path | 가장 느린 경로의 시작점·끝점·논리/배선 지연 |
| Check Timing | 클록이나 입력·출력 시간 제약이 빠진 경로가 있는지 |

WNS만 양수라고 통과시키지 않습니다. setup·hold·pulse-width, 제약 누락, 배선 완료, DRC와 자원 적합성을 확인합니다. [AMD report_timing_summary](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/report_timing_summary)에 같은 종류의 분석이 설명되어 있습니다. 목표 주파수를 곧바로 실제 FPS로 바꾸지 마세요. 한 이미지에 필요한 모든 클록과 적재·대기 시간이 별도로 있습니다.

## 5. Windows에서 재실행하기

이 프로젝트 위치에는 한글과 공백이 있습니다. 실제 Windows Vivado 2025.1 실행에서 경로를 잘못 읽는 문제가 나왔습니다. `run_full.ps1`은 필요한 RTL·Tcl·XDC만 영문 임시 경로로 복사하고 SHA-256이 같은지 확인한 뒤 실행합니다. 결과는 원래 프로젝트의 `build/zedboard_full_runs/run_.../`로 복사합니다. 원본 RTL은 바꾸지 않습니다.

PowerShell에서 저장소 루트로 이동합니다. Vivado 설치 위치가 다르면 `-VivadoPath`를 바꾸세요.

```powershell
& ./board/zedboard/run_full.ps1 -Action synth -VivadoPath 'C:/Xilinx/2025.1/Vivado/bin/vivado.bat'
```

배치·배선까지 요청하려면 다음 명령을 사용합니다. 자원이 넘치거나 도구 오류가 있으면 실패를 기록하고 멈춥니다. 보고서가 일부 생성됐다고 전체 통과로 적지 마세요.

```powershell
& ./board/zedboard/run_full.ps1 -Action route -VivadoPath 'C:/Xilinx/2025.1/Vivado/bin/vivado.bat'
```

임시 폴더 경로에도 한글이 있다면 사용 가능한 영문 경로를 `-StageBase`로 지정하세요. 스크립트는 실행마다 새 폴더를 만들며 기존 결과를 삭제하지 않습니다. 임시 폴더에는 소스 사본과 체크포인트가 남으므로 저장 공간도 확인합니다.

영문 경로에서 직접 실행하는 경우에는 운영체제와 관계없이 다음 Tcl을 사용할 수 있습니다.

기본 `-Variant fpga`는 BRAM 포트 버전입니다. 원래 소스는 `-Variant baseline`, 배열만 편 버전은 `-Variant flat`으로 선택할 수 있습니다. 둘은 실패 원인을 재현하는 진단용입니다. Tcl 직접 실행은 마지막 인자로 `fpga`를 전달합니다.

```bash
vivado -mode batch -nojournal -log vivado.log -source board/zedboard/build_full.tcl -tclargs synth fpga
```

`build_basic.tcl`은 작은 Conv+VIO 실습입니다. 이 전체 코어 실험에는 `build_full.tcl`을 사용합니다. 실제 보드 핀용 `basic.xdc`와 이번 OOC 시간 가정 `full_core.xdc`도 서로 다른 파일입니다.

## 6. 결과를 찾고 보관하기

| 파일 | 용도 |
| --- | --- |
| launch_manifest.json | 실행 날짜·도구 경로·part·복사한 소스 해시 |
| vivado.log | 실행 명령·라이선스·메모리 추론·경고·실패 원인 |
| output/reports/status.txt | 요청한 단계의 완료/실패와 중단 위치 |
| post_synth_utilization.rpt | 합성 자원 사용량 |
| post_synth_hierarchical.rpt | 계층별 자원 사용량 |
| post_synth_timing_summary.rpt | 합성 직후의 시간 추정 |
| post_synth_check_timing.rpt | 클록·입출력 제약 누락 검사 |
| post_synth_worst_setup.rpt | 가장 느린 경로의 상세 |
| post_route_* | 배치·배선이 완료된 경우의 실제 배선 반영 보고서 |
| post_route_status.rpt | 배선 완료 상태 |

요약 도구는 보관한 `source_snapshot/`을 실행 manifest의 해시와 대조합니다. 현재 작업 파일과 같은지도 별도로 기록하므로 이전 실행의 소스와 새 소스를 혼동하지 않습니다. 스크립트가 출력한 run 폴더를 아래 명령에 넣습니다. 실패한 실행도 원본 로그를 보존하며, 없는 수치를 0이나 PASS로 만들지 않습니다.

```powershell
python -m tools.summarize_vivado --run build/zedboard_full_runs/run_날짜_식별자
```

`results/vivado_full/summary.json`과 원본 보고서 사본을 읽습니다. `COMPLETE`는 요청한 도구 실행이 끝났다는 뜻입니다. 자원이 들어가고 타이밍까지 통과했다는 판정은 요약의 `verdict`와 개별 보고서로 따로 확인합니다.

## 7. 이번 실행 결과

**2026-11-02, Vivado 2025.1로 실제 합성 완료. 현재 ZedBoard에는 자원 초과이며 100 MHz 시간 조건도 만족하지 못했습니다.** 배치 전 DRC가 `UTLZ-1`로 중단되어 배선 후 타이밍과 bitstream은 없습니다. 오류를 경고로 낮추는 옵션은 사용하지 않았습니다.

| 합성 자원 | Used | Available | Util% | 판정 |
| --- | --- | --- | --- | --- |
| Slice LUTs | 88,171 | 53,200 | 165.73% | 초과 |
| LUT as Memory (LUT의 부분집합) | 51,372 | 17,400 | 295.24% | 초과 |
| Slice Registers / FF | 741 | 106,400 | 0.70% | 용량 이내 |
| Block RAM Tile | 16 | 140 | 11.43% | 용량 이내 |
| DSP | 18 | 220 | 8.18% | 용량 이내 |

LUT as Memory를 Slice LUTs에 다시 더하지 않습니다. 메모리로 사용할 수 있는 LUT는 전체 LUT 중 일부여서 별도의 작은 한도가 있습니다. BRAM이 남아 있어도 Weight가 LUT RAM으로 합성되면 이 한도를 넘을 수 있습니다.

| 합성 후 시간 항목 | 결과 |
| --- | --- |
| 목표 | 10.000 ns, 100 MHz |
| WNS / TNS | −121.450 ns / −86,226.281 ns |
| WHS / THS | −0.812 ns / −219,269.781 ns |
| WPWS / TPWS | 3.750 ns / 0.000 ns |
| Check Timing | 12개 검사 종류의 집계가 모두 0 |
| 가장 나쁜 setup 경로 | `op_id_reg[1]/C` → `feature_mem/mem_reg_0_0/ADDRARDADDR[10]` |
| 그 경로의 data delay | 추정 130.800 ns, 논리 365단계(CARRY4 327개 포함) |
| 배치·배선 후 시간 결과 | NOT_AVAILABLE, 배치 전 자원 DRC에서 중단 |

시간 제약이 빠져서 숫자가 없는 경우와, 제약을 걸었지만 지키지 못한 경우를 구분하세요. 이번에는 클록·입출력 제약 누락 집계는 0이지만 실제 계산 경로가 목표를 넘었습니다. 합성 직후 숫자에서 보드 Fmax나 FPS를 확정하지 않습니다.

### 로그에서 확인한 원인과 다음 개선 순서

실제 RAM 추론 표에서 `feature_mem/mem_reg`는 BRAM 16개로 매핑됐습니다. 반면 `w_mem_reg`, `b_mem_reg`, `n_mem_reg`, `r_mem_reg`는 Distributed RAM으로 기록됐습니다. `w_mem_reg`의 추론 크기는 주소 폭에 따른 512 K×8, RAM64M 12,579개로 표시됩니다. 실제 모델의 Weight 수 268,336개가 늘어났다는 뜻이 아니라 도구가 만든 메모리 주소 공간과 패딩까지 포함한 중간 매핑입니다. 최종 용량 판정에는 Used/Available 표와 배치 DRC를 사용합니다.

1. Weight·bias/N/r도 BRAM의 동기식 읽기 포트로 옮겨 LUT RAM 과다 사용을 줄입니다. 상수를 지우거나 작은 layer로 바꿔서 전체 모델을 대신하지 않습니다.
2. 가장 나쁜 경로가 작업 번호에서 feature 주소까지 이어집니다. 코드의 32bit 가변 나눗셈·나머지·곱셈 주소식을 우선 점검합니다. 고정 Shape의 shift/명시적 카운터, 작업 속성의 레지스터 저장, 주소 계산 단계 분리를 검토할 수 있습니다. 각 식의 기여도는 후속 비교 합성으로 확인해야 합니다.
3. 변경 후 동일한 정수 Golden·61경계·0→1→0·Stall·Reset을 다시 시험하고 자원·타이밍을 재측정합니다. 마지막에 실제 시스템 wrapper의 클록·입출력 조건으로 배치·배선과 보드 시험을 진행합니다.

이 순서는 관측한 실패 원인을 바탕으로 한 다음 개선안입니다. 이번 결과를 ZedBoard 적합·100 MHz 통과·실제 보드 실행 완료로 표시하지 않습니다.

### BRAM 버전의 계산은 다시 확인했나요?

[revision 5a2f8eed의 전체 정수 회귀 시험](https://github.com/tsi03048/resnet20-accel/actions/runs/41419755891)도 통과했습니다. 정상 sample 0→1→0(예측 cat 3→ship 8→cat 3), MAC·trace·응답 Stall, 세 위치 Reset 후 sample 1 재적재까지 완료 5회입니다. 매회 61경계·점수10개·예측이 모두 같고, 경계 원소 2,760,420개 불일치 0입니다. 네 종류의 잘못된 Golden 검출, loader 10개 거부, overflow·RNE·argmax 시험도 통과했습니다. 내려받은 첫 정상 sample 0 CSV 274,506행을 로컬에서 다시 비교했습니다. 실제 이미지는 2종이며 10,000장 RTL 정확도 평가가 아닙니다.

```bash
bash tb/full_e2b_fpga_v1/run.sh
```

위 회귀 시험은 Linux/WSL의 Verilator·C++·NumPy 환경에서 실행합니다. Vivado 합성과는 별개의 명령입니다. [기능 결과](../results/full_fpga_rtl_actual.json) · [실행 소스·artifact 식별](../results/full_fpga_rtl_evidence.json). 기존 시험과 새 보고서 판독 검사를 포함한 Python 검사 37개도 통과했습니다.

원본 보고서와 실행 소스 사본은 `results/vivado_full/fpga/`, 실패 원인을 확인한 비교 기록은 `results/vivado_full/baseline/` 및 `flat/`에 보관합니다. 요약은 [실제 Vivado 결과](../results/vivado_full_actual.json)에서 읽습니다. 전체 원본과 다시 실행할 소스는 실습 ZIP에도 포함합니다.

## 8. 직접 설명하고 제출하기

1. 61경계가 맞는데 FPGA에 못 들어갈 수 있는 이유를 설명하세요.
2. `Used > Available`인 항목이 하나라도 있을 때의 판정을 적으세요.
3. 배열 크기와 실제 BRAM 개수가 다른 이유를 설명하세요.
4. 100 MHz 제약과 실제 FPS가 다른 이유를 설명하세요.
5. 합성 후 WNS와 배치·배선 후 WNS 중 무엇을 보드 구현 판단에 사용해야 하나요?

날짜·Vivado 버전·part·OOC 범위·source 해시·목표 주기·입출력 시간 가정·LUT/FF/BRAM/DSP Used/Available·WNS/TNS/WHS·제약 누락·최종 완료 단계·오류·수정 제안을 제출합니다. 직접 돌리지 않은 항목은 NOT_RUN, 도구가 실패해 숫자가 없는 항목은 NOT_AVAILABLE로 구분하세요. 배포된 결과를 연 것과 본인이 재실행한 것도 구분합니다.
