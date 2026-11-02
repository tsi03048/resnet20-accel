# E8-D. 전체 코어를 BRAM에 넣고 100 MHz로 동작하게 만들기

[E8-C](full_vivado_zedboard.md)에서는 실제 합성 결과가 용량을 넘고 시간 조건도 실패했습니다. 이번에는 계산 규칙과 실제 상수를 그대로 두고 **숫자를 저장하고 전달하는 회로 구조**를 고칩니다. 이 실습은 [S5](learning/S5.md)의 선택 확장입니다.

## 1. 먼저 구분할 세 가지

| 확인 | 질문 | 이번에 보는 증거 |
| --- | --- | --- |
| 계산 | 같은 입력에서 같은 정수가 나오는가? | 실제 sample 0→1→0, 61경계·점수·예측 |
| 크기 | 이 FPGA의 자원 안에 들어가는가? | 합성 및 배치·배선 후 LUT/FF/BRAM/DSP |
| 시간 | 매 10 ns의 시간 약속을 지키는가? | 배선 후 setup·hold·pulse-width, 제약·배선·DRC 검사 |

기준 모델은 ResNet-20·CIFAR-10·E2-B v1 그대로입니다. Weight를 줄이거나 정수 눈금을 다시 선택하지 않았습니다. Golden을 회로 안에 넣지 않습니다. Host는 입력과 계수만 넣으며 중간 숫자는 실제 회로가 계산해 이어 저장합니다.

## 2. 왜 배열에 BRAM이라고 적는 것만으로 부족했을까요?

이전 실행에서 큰 Weight 배열이 LUT RAM으로 만들어졌습니다. RAM 배열을 어떤 포트로 언제 읽는지부터 바꿔야 합니다. 이번 `sync_bram.sv`는 쓰기 포트와 **클록에 맞춘 읽기 포트**를 분리하고, 읽은 값을 한 번 더 레지스터에 저장합니다. 주소를 요청한 뒤 대기 단계를 거쳐 값을 사용합니다.

Weight는 268,336 bytes입니다. 19bit 주소 공간 전체를 하나의 큰 메모리로 잡으면 필요 이상으로 커질 수 있어 다음 두 구간으로 나눴습니다.

| 구간 | 실제 주소 | 예약한 깊이 |
| --- | --- | --- |
| 앞부분 | 0~262,143 | 262,144×8bit |
| 뒷부분 | 262,144~268,335 | 8,192×8bit, 그중 6,192개 사용 |

총 예약은 270,336 bytes입니다. 읽기를 요청할 때 어느 구간인지도 저장해서, 지연된 읽기 결과와 같은 구간을 선택합니다. 끝 주소나 구간 경계가 다른 메모리와 겹치면 계산 결과가 틀립니다.

| 전용 메모리 | 36 Kb BRAM Tile 환산 |
| --- | ---: |
| Weight 두 구간 | 66 |
| 세 논리 feature bank | 16 |
| Bias, N | 각각 1 |
| Shift | 0.5 |
| 합계 | 84.5 / 140 |

0.5는 18 Kb 블록입니다. 단순 payload bit 수와 실제 배치 블록 수는 깊이·폭·포트 때문에 다를 수 있습니다. 이번 수치는 실제 Vivado 매핑 보고서로 확인합니다.

## 3. 주소 계산을 작은 회로로 바꾸기

가로·세로 크기는 32, 16, 8 또는 1로 고정되어 있습니다. 실행 중 큰 정수 나눗셈·나머지 연산으로 좌표를 구할 필요가 없습니다.

| 기존 표현 | 바꾼 방법 |
| --- | --- |
| 출력 번호를 H×H로 나누기 | 크기별 정해진 비트 묶음으로 채널·줄·칸 선택 |
| 항 번호를 9와 3으로 나누기 | 입력 채널·필터 줄·필터 칸의 작은 카운터 |
| 채널마다 Weight 시작 주소 다시 곱하기 | 채널이 끝날 때 시작 주소에 K만 더하기 |
| 작업 번호에서 큰 주소식까지 바로 연결 | 작업 속성과 계산한 주소를 각각 레지스터에 저장 |

예를 들어 32×32 출력에서 한 채널은 1,024개입니다. 출력 번호의 아래 10bit가 공간 위치이고, 그중 아래 5bit가 x, 그 위 5bit가 y입니다. 이것이 /1024, /32, %32와 같은 결과를 만듭니다. 16×16에서는 아래 4bit씩, 8×8에서는 아래 3bit씩 고릅니다.

필터의 kx·ky는 0→1→2 순서로 돌고, 한 필터가 끝나면 입력 채널을 늘립니다. Padding은 범위를 벗어났는지 확인해 code 0을 사용합니다. Transition의 stride2와 Option A는 짝수 공간 좌표·가운데 채널 배치를 유지합니다.

## 4. 긴 계산을 여러 클록으로 나누기

주소 요청·BRAM 대기·입력 확보·8bit 곱·32bit 누산을 단계별로 처리합니다. MAC은 곱한 값을 중간 합에 더하는 한 번의 계산입니다. `compute_ready=0`이면 MAC의 중간 합과 항 번호를 유지합니다.

Requant와 Add의 넓은 곱은 큰 조합 곱셈기 대신 **한 bit씩 곱해 더하는 31회 과정**으로 계산합니다. Add는 Main과 Skip의 두 곱을 더한 뒤 RNE를 한 번 적용합니다. N은 0 이상인 31bit 계수이며, 넓은 결과는 signed INT64입니다.

반올림도 한 bit씩 산술 시프트하면서 마지막 버린 bit와 그보다 아래 bit가 하나라도 1인지 기억합니다. 마지막 bit가 1이고 아래 bit가 있거나 남은 정수가 홀수이면 1을 더합니다. 이것이 음수까지 포함한 ‘정확히 절반이면 짝수’ 규칙입니다. 그 뒤 signed INT8·ReLU INT8·FC signed INT32 중 정해진 범위로 자릅니다.

클록 한 주기의 계산은 짧아지지만 결과 하나에 필요한 클록 수는 늘었습니다. **100 MHz 통과가 한 클록에 한 출력이나 FPS 향상을 뜻하지는 않습니다.** 이번 목표는 전체 모델의 계산 일치와 자원·시간 조건입니다.

## 5. Setup과 Hold를 함께 맞추기

Setup은 너무 늦게 도착하는 값, Hold는 너무 일찍 바뀌는 값을 검사합니다. Setup WNS만 양수여도 Hold WHS가 음수이면 통과가 아닙니다.

이번 OOC 코어의 짧은 입력 경로에는 실제 LUT1 지연 버퍼를 추가했습니다. LUT1의 진리표 `2'b10`은 입력 0→출력 0, 입력 1→출력 1이므로 숫자나 클록 수는 바꾸지 않습니다. 필요한 동기 입력 61bit에 8단계를 적용합니다. 비동기 점수 읽기 주소는 이 버퍼를 거치지 않습니다. 버퍼가 실제로 남도록 DONT_TOUCH를 사용하며 자원·최대/최소 지연을 모두 보고서로 검사합니다.

버퍼 길이는 다른 장치·클록·주변 회로에도 그대로 맞는 값이 아닙니다. 바꿀 때는 setup과 hold를 모두 다시 측정해야 합니다. Verilator에는 같은 LUT1 진리표 모델을 넣어 **버퍼를 포함한 최종 top**을 시험합니다. 모델 파일은 실제 합성에 사용하지 않습니다.

## 6. 이번에 검증하는 물리 경계

| 설정 | 값 |
| --- | --- |
| FPGA | `xc7z020clg484-1` |
| Vivado | 2025.1 |
| Top | `full_model_timed`, 그 안의 전체 `full_model` 포함 |
| 클록 | 10.000 ns, 100 MHz |
| 데이터 입출력 예산 | max 2.000 ns, min 0.000 ns |
| OOC 클록 소스 | 외부 전역 클록의 진입 위치 `HD.CLK_SRC=BUFGCTRL_X0Y0` |

클록 주기를 늘리거나 거짓 경로·다중 주기 예외로 검사를 빼지 않았습니다. 모든 데이터 포트를 유지했습니다. 이 경계는 시스템 안에 넣을 코어의 경계이며, 외부 BUFG·PS/DDR/AXI·실제 보드 핀과 bitstream까지 구성한 보드 top은 아닙니다. 실제 시스템에 연결할 때는 그 클록 소스·주변 경로를 포함해 다시 배치·배선합니다. Zynq의 PS7 구성 경고도 OOC 범위와 실제 보드 구성을 구분해 읽습니다.

[AMD OOC 설명](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/synth_design) · [동기식 BRAM과 분산 RAM의 차이](https://docs.amd.com/r/2025.1-English/ug901-vivado-synthesis/Choosing-Between-Distributed-RAM-and-Dedicated-Block-RAM)

## 7. 실제 결과와 판정

**Vivado 2025.1 실제 배치·배선 완료, 100 MHz 시간 조건 통과.** 합성 보고서의 추정값으로 대신하지 않고 배선 후 보고서로 판정했습니다.

| 자원 | 이전 E8-C 합성 | v2 배선 후 | 장치 용량 |
| --- | ---: | ---: | ---: |
| LUT | 88,171 | 1,957 (3.68%) | 53,200 |
| 그중 LUT RAM | 51,372 | 0 | 17,400 |
| FF | 741 | 1,759 (1.65%) | 106,400 |
| BRAM Tile | 16 | 84.5 (60.36%) | 140 |
| DSP | 18 | 0 | 220 |

이전 열은 배치가 중단됐던 합성 수치이고, v2 열은 배선 후 수치입니다. 같은 단계의 최종 보드 성능 비교는 아닙니다. DSP가 0이어도 곱셈은 수행하며, LUT와 순차 계산 경로로 구현됐다는 뜻입니다.

| 배선 후 시간·구현 검사 | 결과 |
| --- | --- |
| 목표 주기 | 10.000 ns |
| WNS / TNS | **+0.071 ns / 0.000 ns** |
| WHS / THS | **+0.052 ns / 0.000 ns** |
| WPWS / TPWS | +4.500 ns / 0.000 ns |
| Setup·Hold·Pulse 위반 endpoint | 모두 0 |
| Check Timing | 12개 검사 종류 모두 0 |
| 배선 | 3,325 / 3,325 net 완료, 오류 0 |
| DRC 오류 | 0, OOC의 PS7 구성 경고는 별도 기록 |

Setup 여유는 71 ps, Hold 여유는 52 ps로 작습니다. 이 수치는 지금 고정한 코어·장치·클록 진입 위치·입출력 예산에서의 결과입니다. 더 높은 주파수나 실제 보드 성능을 보장하는 수치로 확대하지 않습니다. 원본: [Vivado v2 결과](../results/vivado_v2_actual.json)와 `results/vivado_v2/final/reports/`.

### 최종 top의 실제 정수 회귀 시험

[revision 4d198f2d 실행](https://github.com/tsi03048/resnet20-accel/actions/runs/41430880747)에서 버퍼를 포함한 `full_model_timed`를 시험했습니다. 실제 sample 0→1→0의 예측은 cat(3)→ship(8)→cat(3)이고 점수10개도 모두 같았습니다. 정상3·Stall1·Reset 회복1의 **완료5회, 매회61경계, 경계 원소 2,760,420개 불일치0**입니다. 실제 이미지는 Test 0/1 두 종류이며 10,000장 RTL 정확도 평가와 구분합니다.

MAC·trace·응답 Stall, 7곳 Reset 취소와 완전 재적재, loader 10개 거부, INT32 overflow 후 Reset, 네 종류의 고의 Golden 오류 검출을 통과했습니다. 순차 반올림은 Fraction 기준 2,000개, 순차 곱셈은 Python 정수 기준 512개 벡터로 확인했고 signed argmax·동점·응답 유지도 검사했습니다. Python 검사 38개도 통과했습니다.

첫 정상 sample 0의 원본 CSV 274,506행을 내려받아 Python으로 다시 대조했고 모두 일치했습니다. 기능 시험과 Vivado가 사용한 활성 RTL의 SHA256도 일치했습니다. [기능 결과](../results/full_fpga_v2_rtl_actual.json), [실행·해시 증거](../results/full_fpga_v2_rtl_evidence.json), [원본 실행 요약](../results/full_fpga_v2_execution.log)을 함께 확인하세요.

## 8. 직접 실행하기

먼저 동봉된 증거 파일이 같은 묶음인지 확인할 수 있습니다. 이 검사는 표준 Python만 사용하며, 실제 Vivado나 시뮬레이터를 실행하는 명령은 아닙니다. `DELIVERED_EVIDENCE_VERIFIED`는 ‘배포 증거 검사’로 기록합니다.

```bash
python -m tools.check_v2_delivery
```

Windows PowerShell에서 저장소 루트로 이동합니다. Vivado가 다른 위치에 있으면 경로를 바꿉니다. 한글 프로젝트 경로 문제를 피하도록 필요한 파일을 영문 임시 경로에 복사하고, 복사 전후 해시를 검사해 실행합니다.

```powershell
& ./board/zedboard/run_full.ps1 -Action route -Variant fpga2 -VivadoPath 'C:/Xilinx/2025.1/Vivado/bin/vivado.bat'
```

출력된 run 폴더를 요약 도구에 넣습니다. 새 이름으로 결과를 보관해 이전 실행을 덮어쓰지 마세요.

```powershell
python -m tools.summarize_vivado --run build/zedboard_full_runs/run_날짜_식별자 --output results/my_vivado_v2
```

`status=COMPLETE`는 도구 실행이 끝났다는 뜻입니다. `verdict=ROUTED_CORE_PASS`, Used≤Available, WNS/WHS/WPWS≥0, TNS/THS/TPWS=0, 제약 누락 0, 배선 오류 0, DRC 오류 0까지 확인합니다.

배포 ZIP의 `checkpoints/post_route.dcp`는 배선된 회로의 저장본입니다. Vivado 2025.1에서 Open Checkpoint로 열어 자원과 경로를 살펴볼 수 있습니다. FPGA를 프로그래밍하는 bitstream 파일과는 다릅니다. 다시 만든 결과는 `build/zedboard_full_runs/run_.../output/post_route.dcp`에 생깁니다.

기능 시험은 Linux/WSL의 NumPy·Verilator·C++·make 환경에서 실행합니다. GPU·재학습·사진 다운로드는 필요 없습니다.

```bash
python -m pip install numpy
bash tb/full_e2b_fpga_v2/run.sh
```

정상 0→1→0, MAC/trace/응답 Stall, 오류 거부, Reset을 실행하고 원본 CSV도 다시 비교합니다. `mode 6~9`는 Golden을 한 bit 틀리게 바꾼 검사이므로 지정된 mismatch로 실패해야 전체 검사가 통과합니다. Timeout이나 빌드 실패를 mismatch 검출로 세지 않습니다.

Reset은 계수 읽기, Weight 읽기, 순차 곱셈, 순차 RNE, Stem, Transition, 최종 응답 대기의 7곳에서 넣습니다. 매번 준비 상태와 작업을 취소하고 완전히 재적재합니다. BRAM 자체를 0으로 지우지는 않습니다. 마지막에는 sample 1을 끝까지 실행해 61경계·점수·예측을 확인합니다.

## 9. 본인 기록과 설명

1. Weight 뒤 구간의 주소 262,144와 마지막 주소 268,335가 어느 메모리 위치인지 설명하세요.
2. 주소를 요청한 다음 클록에 바로 계산하지 않고 기다리는 이유를 설명하세요.
3. 한 주기의 계산을 줄이면서 총 클록 수는 왜 늘어났나요?
4. Setup이 통과했는데 Hold가 실패하면 어떤 판정을 해야 하나요?
5. Reset 후 BRAM에 예전 숫자가 남아 있어도 올바른 결과를 낼 수 있는 조건은 무엇인가요?

날짜·명령·source 해시·패키지 해시·Vivado 버전·part·클록과 입출력 예산을 적습니다. 정상 예측 순서, 61경계 불일치 수, Stall/Reset 위치, Used/Available, 배선 후 WNS/WHS/TNS/THS, 배선 오류·제약 누락·DRC를 함께 제출하세요. 기준 결과 열람과 본인 재실행을 구분하고 실행하지 않은 범위는 NOT_RUN으로 남깁니다.
