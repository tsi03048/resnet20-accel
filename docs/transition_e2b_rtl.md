# E16-B. 실제 정수 Transition — stride2·Option A를 RTL로 비교하기

이번 목표는 **실제 ResNet-20의 두 Transition Block L2.0·L3.0를 실행하고, Conv 중간값·shortcut 주소/값·최종 출력을 Golden과 일치시키는 것**입니다.
[Residual 단위 실습](residual_e2b_rtl.md)과 [Stem→Residual 연결](stem_residual_e2b_rtl.md)을 이해한 뒤 진행합니다. 처음이라면 이론의 Channel·Shape·Residual·정수 눈금을 먼저 읽습니다.

## 1. 먼저 결과를 확인하고 실행하기

GitHub **Actions → Actual integer Transition blocks → transition-real-integer**에서 로그를 봅니다.
완료 실행의 `transition-real-integer-evidence`에는 두 Stage의 CSV·파형·로그·요약이 있습니다.

직접 실행하려면 Ubuntu 24.04 또는 Windows의 WSL Ubuntu에서 저장소 최상위로 이동합니다.

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv build-essential verilator
python3 -m venv .venv
source .venv/bin/activate
python -m pip install numpy
bash tb/transition_e2b_v1/run.sh
```

NumPy·Verilator·C++ 빌드 도구를 사용합니다. GPU·새 학습·데이터 다운로드는 필요하지 않습니다.
스크립트가 `STAGE=2`와 `STAGE=3`을 각각 빌드합니다. STAGE는 빌드 시 정하는 대상이며 런타임에 바꾸는 명령이 아닙니다.
전체 성공은 마지막 `status: PASS`로 확인합니다. 고의 mismatch 시험은 해당 실행이 실패해야 전체 통과입니다.

## 2. 무엇이 달라지나

| 대상 | 적재하는 실제 입력 | X | H·M·Skip·Y | Conv1 K | Conv2 K |
|---|---|---|---|---|---|
| L2.0, STAGE=2 | sample 0의 L1.2 출력 | `[1,16,32,32]` | `[1,32,16,16]` | 144 | 288 |
| L3.0, STAGE=3 | 같은 sample 0의 L2.2 출력 | `[1,32,16,16]` | `[1,64,8,8]` | 288 | 576 |

K는 출력 하나를 만드는 곱 항의 개수입니다. Conv1과 Conv2의 입력 채널 수가 달라 K도 달라집니다.
각 Transition에서 Conv1은 1,179,648 MAC, Conv2는 2,359,296 MAC, 합계3,538,944 MAC입니다.
두 전환의 MAC 수가 같은 것은 채널이 늘고 공간이 줄기 때문이며, FPGA 속도가 같다는 뜻은 아닙니다.

```text
X 보존 ──→ Conv1(stride2) → H(ReLU) → Conv2(stride1) → M(음수 유지)
  │                                                       │
  └── 짝수 좌표 선택·채널 앞뒤0 → Skip ── 단위 정렬 Add ──┘
                                             ↓
                                   RNE 한 번·ReLU·포화 → Y
```

새 실제 계수용 구현은 `rtl/transition_e2b_v1/`입니다. 하나의 Conv 계산 경로를 두 단계에 순차 재사용하며 출력 채널별 Bias/N/Shift를 선택합니다.
기존 E16의 `/4` 진단 예제·두 static Core·과거 로그는 `historical/e12-e21/`에 그대로 보존합니다. 실제 DSP·BRAM 사용량은 합성 후 확인합니다.

## 3. stride2를 작은 Window로 생각하기

입력 채널 하나에서3×3 필터의 중심은 출력 좌표에 따라 `(0,0) → (0,2) → (0,4)`처럼 두 칸씩 이동합니다.
평균을 내거나2×2를 한꺼번에 더하는 연산이 아닙니다. Weight를 곱하는3×3 Conv의 이동 간격입니다.

```text
Conv1: iy=2*oy+ky-1, ix=2*ox+kx-1
Conv2: iy=oy+ky-1,   ix=ox+kx-1
입력 범위 밖은 code0. Bias는 출력마다 한 번만 더함.
```

Testbench는 모든 항의 입력/Weight 주소·Padding 여부와 등록된 X/W 값을 따로 검사합니다.
누산과 최종 code가 같다는 것뿐 아니라, 올바른 window와 채널에서 값을 읽었는지도 확인합니다.

## 4. Option A는 어디서 읽나

출력 공간은 절반, 출력 채널은 두 배입니다. 가운데 채널만 X의 짝수 좌표를 읽으며 앞뒤 채널은 Skip code0입니다.

| 대상 | 앞쪽0 채널 | X를 읽는 채널 | 뒤쪽0 채널 |
|---|---|---|---|
| 16→32 | 0..7 | 8..23 | 24..31 |
| 32→64 | 0..15 | 16..47 | 48..63 |

```text
가운데일 때 Skip[co,oy,ox] = X[co-Cin/2, 2*oy, 2*ox]
그 밖에는 Skip=0, X read 없음
출력 원소 주소 = (co*OH+oy)*OH+ox
X 원소 주소 = ((co-Cin/2)*H+2*oy)*H+2*ox  (가운데에서만 유효)
```

L2.0의 `Skip[8,1,2]`는 `X[0,2,4]`입니다. 출력 주소는2,066이지만 X 주소는68입니다.
출력 주소를 그대로 X에 쓰면 다른 원소가 섞입니다. 앞뒤0 채널에서 음수 채널 주소를 잘라 RAM을 읽어도 안 됩니다.
실제 입력값이0일 수도 있으므로 **code가0인지와 X를 읽지 않는 zero channel인지는 다릅니다.**
RTL의 `skip_read/skip_read_addr`는 실제 read, `skip_from_x/skip_addr`는 Y에 대응하는 보관된 출처 정보입니다.
대기 중에는 이 출처와 Main·Skip·Add wide·Y를 함께 유지합니다.

작은 예: X의 두 채널이 각각1..16,101..116인4×4라면 Skip 네 채널의2×2 값은 다음과 같습니다.

```text
co0: 0,0,0,0
co1: 1,3,9,11
co2: 101,103,109,111
co3: 0,0,0,0
```

## 5. Skip이0이어도 Y는0이 아닐 수 있다

Option A의0은 shortcut에 더할 값입니다. Main 결과를 버리는 mask가 아닙니다.
실제 L2.0의 출력 주소0에서는 `H=7, M=4, Skip=0 → Y=3`입니다.

L2.0의 정수 Add 계약은 다음과 같습니다.

```text
wide = M*806170754 + Skip*1245146209
Y = clip[0,127](RNE(wide / 2^30))
```

| L2.0 출력 주소 | X 출처 | M | Skip | Y |
|---|---|---|---|---|
| 0 | 읽지 않음 | 4 | 0 | 3 |
| 2048 | X 주소0 | -6 | 18 | 16 |
| 2066 | X 주소68 | 1 | 6 | 8 |
| 6144 | 읽지 않음 | -7 | 0 | 0 |

L3.0은 별도 계수 `Nmain=1507819355, Nskip=1437447445, r=31`을 사용합니다.
Main·Skip의 Scale을 맞춘 넓은 합에 RNE를 한 번 적용하고 ReLU·포화합니다. 단순8-bit 덧셈이나 경로별 선행 반올림으로 바꾸지 않습니다.
Conv2 뒤에는 ReLU를 넣지 않습니다. 음수 Main도 Skip과 합친 뒤 판단합니다.

## 6. 실제 상수와 Golden의 출처

`tools/transition_vectors.py`는 고정 E2-B 패키지와 sample 0의61경계 재현·hash를 먼저 검사합니다.
L2.0·L3.0의 입력·두 Weight/Bias/N/Shift·Add 계수와 acc1/H/acc2/M/Skip/Add wide/Y를 추출합니다.
Skip은 pad/slicing 대신 출력 좌표→X 주소의 작은 정수 루프로도 계산해 원래 Golden과 대조합니다.

`reference/e2b_v1/transition_vectors/manifest.json`이 바이트 hash·Shape·순서를 고정합니다. hex는 실행할 때 재생성하며, manifest가 달라지면 중단합니다.
주소 기준의 -1은 “X read 없음” 표시입니다. RTL에 적재하는 주소나 데이터가 아닙니다.
DUT는 기대값이나 `$readmemh`를 갖지 않습니다. Testbench가 실제 입력·상수를 native loader로 적재하고 기대값은 비교에만 씁니다.

이번 입력은 저장한 L1.2/L2.2 경계입니다. 앞선 Stem→L1.0 연결에 바로 붙인 전체 모델 실행은 아닙니다.
같은 원본 sample 0의 두 단위 시험이며 서로 다른 두 이미지로 세지 않습니다.

## 7. 적재와 Buffer 수명

| cfg_kind | 의미 | Stage2 개수 | Stage3 개수 |
|---|---|---|---|
| 0 | X | 16,384 | 8,192 |
| 1 | W1 | 4,608 | 18,432 |
| 2 | W2 | 9,216 | 36,864 |
| 3,4 | B1,B2 각각 | 32 | 64 |
| 5,6 | N1,N2 각각 | 32 | 64 |
| 7,8 | r1,r2 각각 | 32 | 64 |
| 9 | Main N·Skip N·r | 3 | 3 |

주소는 종류마다0부터 시작하는 원소 순번이며16-bit입니다. Stage3 W2의 마지막 주소36,863은32,767을 넘습니다.
8-bit 입력/Weight는 하위8-bit만 보내며 상위24-bit는0입니다. Weight -128은 이 프로파일에서 거부합니다.
Bias는 signed INT32 비트열, N은 비음수 signed INT32, r은0..31입니다.

`load_begin → 전체 적재 → prepared → start` 순서입니다. 상승 에지의 `cfg_valid && cfg_ready`에서만 word를 받습니다.
같은 주소를 다시 써도 준비 개수는 늘지 않으며, 불완전 적재나 Busy 중 시작은 거부합니다.
출력은 valid와 ready가 함께1일 때 수락합니다. 마지막 Y 뒤 완료 응답도 ready까지 보관하며, 응답 수락 때 done이 한 클록 나옵니다.

X는 마지막 Option A까지 보존합니다. H와 Y는 같은 B 영역을 사용하지만 Conv2가 H를 전부 읽은 뒤에만 Y를 씁니다.
X/H/M의 INT8 payload 합은 Stage2 32KiB·Stage3 16KiB입니다. Weight·계수·valid tracker·실제 FPGA 배치는 이 숫자에 포함하지 않습니다.

## 8. 시험 범위와 파형

각 Stage에서 정상 연속2회·대기1회·Reset 복구1회·불법 적재 뒤 복구1회, 합계5개 Block을 완료합니다.
Reset은 Conv1·Conv2·앞쪽 zero channel의 Y 대기·가운데 X read 채널의 Y 대기 네 곳에서 취소합니다.
MAC·Conv 출력·Y·완료 응답의 대기와 Busy 중 적재/start 차단도 확인합니다.

고의 오류는 acc1·M·가운데 Skip·Y·Add wide·앞쪽 zero Skip·Skip 주소의7종입니다. 각 실행은 오류를 검출해 실패해야 합니다.
별도 합성 overflow 상수는 연산 중단·출력/완료 응답 억제를 확인하는 시험이며 정확도 결과가 아닙니다.
새 소스의 strict lint, 모든 Conv 주소/pair·누산·중간값·Shortcut read/zero 개수·X 보존·B=Y·C=M을 검사합니다.

```text
results/transition_rtl/stage2/first500.vcd       # stride2 첫 계산 500클록
results/transition_rtl/stage2/option_a_window.vcd # zero→중앙 채널 경계 500클록
stage3/에도 같은 두 파일
```

파형은 별도 실행의 짧은 창입니다. 전체 완료 증거는 mode별 Scoreboard와 CSV·summary입니다.
Mode0 CSV는 각 Stage의 두 작업에서 acc/H/acc/M/Skip/wide/Y를 전부 다시 비교합니다.

## 9. 결과와 제출

2026-11-02 [revision 43cd6a45의 전체 자동 시험](https://github.com/tsi03048/resnet20-accel/actions/runs/41404611983)이 Verilator 5.020에서 통과했습니다.

| 완료분의 비교 | L2.0, 5회 | L3.0, 5회 | 합계 |
|---|---|---|---|
| Conv1/Conv2 누산값 | 81,920 | 40,960 | 122,880 |
| H/M/Y code | 122,880 | 61,440 | 184,320 |
| Skip code | 40,960 | 20,480 | 61,440 |
| Add wide | 40,960 | 20,480 | 61,440 |
| Option A X read | 20,480 | 10,240 | 30,720 |
| read 없는 zero token | 20,480 | 10,240 | 30,720 |

모든 비교의 불일치는0입니다. 정상 완료10개는 같은 원본 sample 0의 두 Block을 각각5회 실행한 결과입니다.
Reset 취소8회·고의 Golden 오류14회·불법 적재28회·overflow2회도 검출했고, 정상 CSV73,728행을 NPZ 기준으로 다시 비교했습니다.
내려받은 결과를 로컬에서 재검산했으며 실행 소스4개의 hash도 대조했습니다. Python 시험28개도 통과했습니다.

고정 실행 증거는 `results/transition_rtl_actual.json`, 재실행 요약은 `results/transition_rtl/summary.json`입니다.
제출물은 실행 revision·package identity·도구 버전·두 Stage의 summary/로그·주소2066→68 설명·zero Skip이 Y를 지우지 않는 예·미실행 범위입니다.

이번 범위는 두 Transition의 실제 정수 단위 RTL입니다. 모든 Block을 잇는 모델 실행기·GAP/FC·최종 분류·합성/STA·AXI/DMA·보드는 후속입니다.
Verilator 결과를4-state X/Z 전파 시험이나 실제 FPGA 메모리 추론·성능 실측으로 해석하지 않습니다.
