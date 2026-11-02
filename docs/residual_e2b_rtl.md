# E14-B. 실제 정수 Residual Block을 RTL로 비교하기

## 이 장을 읽기 전에

원래 입력을 보관하면서 Conv를 두 번 계산하고, 마지막에 두 결과를 더합니다. 더하기 전까지 원래 입력을 지우지 않는 것이 핵심입니다.

| 본문 표현 | 쉬운 뜻 |
| --- | --- |
| Identity | 이 문서에서는 입출력 크기가 같은 블록 |
| Main·Skip | 계산하는 길·원래 값을 보내는 길 |
| Buffer | 임시 저장 공간 |
| Add wide | 넘침을 막으려고 넓은 비트 수로 계산한 합 |
| overflow | 숫자가 표현 범위를 넘음 |

아래에는 이전 진단 예제와 후속 실제 모델 시험 기록이 함께 있습니다. 각 기록에 적힌 입력·계수·코드 버전·검증 범위를 따로 읽습니다. 과거의 ResNet-56 수치를 현재 ResNet-20에 그대로 적용하지 않습니다.

이번 목표는 **실제 ResNet-20 첫 Identity Block `L1.0`의 Conv1·Conv2·Add를 실행하고 중간값까지 Golden과 일치시키는 것**입니다.
[기본 S0~S4](basic_track.md) → [E2-B](e2b_integer_reference.md) → [실제 Stem](stem_e2b_rtl.md) 뒤의 선택 실습입니다.
처음부터 전체 모델을 구현할 필요는 없습니다. 먼저 한 Block의 입력 보존과 정수 단위를 설명할 수 있으면 됩니다.

## 1. 먼저 실행해 보기

설치 없이 결과를 보려면 GitHub의 **Actions → Actual integer Residual block → residual-real-integer**를 엽니다.
완료된 실행의 `residual-real-integer-evidence`에 로그·CSV·파형·요약이 있습니다.

직접 실행할 때는 Ubuntu 24.04 또는 Windows의 WSL Ubuntu에서 저장소 최상위로 이동합니다.

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv build-essential verilator
python3 -m venv .venv
source .venv/bin/activate
python -m pip install numpy
bash tb/residual_e2b_v1/run.sh
```

이 RTL 실습은 NumPy·Verilator·C++ 빌드 도구를 사용합니다. GPU·PyTorch·데이터 다운로드·재학습은 필요하지 않습니다.
기존 E14 진단 예제의 `/4` 계약 대신 E2-B의 실제 채널별 Bias·N·Shift와 Add 계수를 사용합니다.
`rtl/residual_e2b_v1/`은 실제 계수용 새 공개 구현입니다. 이전 E14 원문·소스·시험 기록은 `historical/e12-e21/`에 유지합니다.

정상 종료는 마지막 JSON의 `status: PASS`입니다. 완료 5작업과 불일치 0을 확인합니다.
Mode 6~9의 mismatch는 고의로 잘못된 기대값을 넣은 시험이며, 스크립트가 그 실패를 확인해야 전체 PASS가 됩니다.
`TRACE_WINDOW_ONLY`는 짧은 파형 실행입니다. 정상 완료 작업 수에 넣지 않습니다.

## 2. Block에서 지켜야 할 세 가지

```text
A: X(입력) ──→ Conv1 → B: H(ReLU 후) → Conv2 → C: M(음수 유지)
   │                                                    │
   └────────── Skip 원본 ──────→ 단위 정렬·Add ←──────────┘
                                     ↓
                           RNE 한 번 → ReLU·포화 → B: Y
```

1. X는 Conv1 뒤에도 보존합니다. 마지막 Add에서 원본이 다시 필요합니다.
2. Conv2 뒤에는 ReLU를 넣지 않습니다. 음수 M이 양수 Skip을 줄이는 기여를 보존합니다.
3. Conv2가 H를 모두 읽고 마지막 M 저장을 마친 뒤에만 B를 Y 저장 공간으로 재사용합니다.

하나의 곱셈·누산 경로를 두 Conv에 순차로 재사용합니다. 두 경로가 있다는 것이 두 계산기를 동시에 실행해야 한다는 뜻은 아닙니다.
X/H/M/Y의 Shape는 모두 `[1,16,32,32]`, 각각 16,384개입니다. 두 Weight는 각각 `[16,16,3,3]`, 2,304개입니다.
출력 하나에 144 MAC, Conv 하나에 2,359,296 MAC, Block 하나에 4,718,592 MAC입니다. Padding 0 항도 셉니다.

## 3. INT8 두 개를 왜 바로 더하면 안 될까?

INT8 code는 숫자 칸의 번호이며 Scale은 한 칸의 크기입니다. 같은 code라도 칸의 크기가 다르면 같은 실수가 아닙니다.
이 실제 Block의 단위는 다음과 같습니다. 설명용 소수이며 RTL에는 저장한 정수 계수를 적재합니다.

| Tensor | 한 code의 Scale |
|---|---|
| X = Stem 출력 | 0.05933695890772061 |
| H = Conv1 출력 | 0.04932610068734237 |
| M = Conv2 출력 | 0.05291201373723548 |
| Y = Add 출력 | 0.07529297025184932 |

계약은 다음과 같습니다. Conv의 Bias/N/r는 출력 채널별이며 Add의 두 N과 r는 이 Tensor 전체에 공통입니다.

```text
acc1 = sum(X*W1) + B1
H = clip[0,127](RNE(acc1*N1 / 2^r1))
acc2 = sum(H*W2) + B2
M = clip[-128,127](RNE(acc2*N2 / 2^r2))
wide = M*1509140679 + X*1692391050
Y = clip[0,127](RNE(wide / 2^31))
```

N은 입력 단위를 출력 단위로 바꾸는 비율을 정수로 표현한 값입니다.
Add는 두 곱을64-bit로 더한 뒤 RNE를 한 번만 적용합니다. 경로별로 먼저 반올림하거나8-bit로 더하면 함수가 달라집니다.
RNE는 가장 가까운 정수로 반올림하되 정확히 중간이면 짝수로 갑니다. 2.5→2, 3.5→4, -2.5→-2, -3.5→-4입니다.

실제 첫 위치는 Conv1 `acc=5429 → H=23`, Conv2 `acc=2199 → M=3`, Skip `X=20`, Add 출력 `Y=18`입니다.
다음 위치는 `M=-7, X=11 → Y=4`로, Conv2 음수의 기여를 관찰할 수 있습니다.
sample 0의 M에는 음수가7,423개 있습니다. Conv2에 ReLU를 잘못 넣으면 Y가3,692개, 단순 code 덧셈이면9,345개, 경로별 반올림이면2,051개 달라집니다.
이 실제 데이터의 차이도 Python으로 재계산해 manifest와 대조합니다.

채널0의 첫 위치를 상수 파일과 대응시키면 다음과 같습니다.

```text
Conv1: 곱의 합 -3810 + Bias 9239 = acc 5429
       N=9292124, r=31 → RNE(5429*N/2^31)=23 → H=23
Conv2: 곱의 합 150 + Bias 2049 = acc 2199
       N=3201348, r=31 → RNE(2199*N/2^31)=3 → M=3
Add:   3*1509140679 + 20*1692391050 = 38375243037
       RNE(38375243037/2^31)=18 → Y=18
```

## 4. Golden의 출처 확인하기

입력은 이미 검증한 같은 sample 0의 Stem 출력입니다. 이번 실행은 저장한 Stem 출력을 Block에 적재합니다.
Stem RTL과 Block RTL의 연속 연결·시작은 다음 통합 시험입니다.

`tools/residual_vectors.py`는 공개한 `reference/e2b_v1/constants.npz`와 `sample0/tensors.npz`를 사용합니다.
먼저 패키지·Golden hash와61경계 NumPy 재실행을 검사하고 L1.0의 값만 hex로 변환합니다.
ASCII·LF·NCHW/OIHW 순서의 hash를 같은 위치의 고정 `residual_l10_vectors/manifest.json`과 대조합니다.
hex는 실행할 때 재생성합니다. 고정 manifest가 다르면 중단하며 기대값을 임의로 다시 고르지 않습니다.

| hex | 용도 | RTL에 적재하는가 |
|---|---|---|
| input, weight1/2, bias1/2, multiplier1/2, shift1/2 | 입력·실제 Conv 상수 | 예 |
| add_config | Main N·Skip N·r의3개 word | 예 |
| acc1_expected, h_expected, acc2_expected, m_expected | 중간 비교 기준 | Testbench만 |
| add_wide_expected, output_expected | Add의 넓은 정수와 최종 code | Testbench만 |

DUT에는 Golden이나 `$readmemh`가 없습니다. Testbench가 파일을 읽어 native loader 포트로 한 word씩 보냅니다.
계층 참조는 상태·메모리 관찰에 사용하며 내부 메모리에 직접 preload하지 않습니다.

## 5. 적재하고 시작하는 순서

| cfg_kind | 의미 | cfg_addr | cfg_data |
|---|---|---|---|
| 0 | X | 0..16383 | 하위8-bit code, 상위24-bit=0 |
| 1, 2 | W1, W2 | 0..2303 | 하위8-bit code, 상위24-bit=0, 0x80 거부 |
| 3, 4 | B1, B2 | 0..15 | signed INT32 비트열 |
| 5, 6 | N1, N2 | 0..15 | 비음수 signed INT32 |
| 7, 8 | r1, r2 | 0..15 | 0..31 |
| 9 | Add 설정 | 0,1,2 | Main N, Skip N, r |

1. Reset 뒤 IDLE에서 `load_begin`을 한 클록 넣어 이전 적재 상태를 무효화합니다.
2. `cfg_valid && cfg_ready`인 상승 에지에서 word를 수락합니다. 종류마다 주소를 0부터 사용합니다.
3. 모든 주소가 채워지면 `prepared=1`입니다. 같은 주소를 중복해도 개수가 늘지 않습니다.
4. `start_ready=1`일 때 `start`를 한 클록 넣습니다. 적재와 시작을 같은 에지에 요청하지 않습니다.
5. Conv 경계는 `conv_valid && conv_ready`에서 수락해 H/M을 저장합니다.
6. 최종 Y는 `y_valid && y_ready`에서 수락하고 B에 저장합니다.
7. 마지막 Y 수락 뒤 `rsp_valid`가 나옵니다. `rsp_ready`로 완료 응답을 수락하면 `done`이 한 클록 나옵니다.

## 6. 주소와 대기 확인하기

```text
out = oc*1024 + oy*32 + ox
t = ci*9 + ky*3 + kx                (0..143)
iy = oy + ky - 1, ix = ox + kx - 1
X/H 주소 = ci*1024 + iy*32 + ix     (이미지 안일 때만)
W1/W2 주소 = oc*144 + t            (종류별 원소 순번)
```

범위 밖 입력은 code 0입니다. NCHW/OIHW 원소 순서이며 byte 순서를 뒤집지 않습니다.
`mac_ready=0`에서는 입력 pair·항 번호·acc를 유지합니다.
`conv_ready=0`이나 `y_ready=0`에서는 valid·주소·데이터를 유지합니다. 완료 응답도 ready까지 유지합니다.
Busy 중 적재는 수락하지 않으며 시작은 거부합니다. 수락한 word의 주소/값이 잘못되면 `load_error`가 한 클록 나옵니다.
Reset은 작업과 prepared를 무효화하므로 시작 전에 전부 다시 적재합니다. 메모리 전체를 0으로 지운다는 뜻은 아닙니다.
Conv의 33-bit 덧셈 검사로 INT32 overflow를 검출하면 `compute_error=1`로 중단하며 성공 응답을 내지 않습니다.

## 7. 시험 범위 읽기

| Mode | 확인하는 것 | 정상 완료 Block |
|---|---|---|
| 0 | 같은 실제 입력으로 연속 두 번 실행·전체 경계 CSV | 2 |
| 1 | MAC/Conv/Y/응답 대기, Busy 중 적재/start | 1 |
| 2 | Conv1 중·Conv2 중·Y 대기 중 Reset 취소 → 재적재·복구 | 1 |
| 5 | 잘못된 word 14개·중복 주소·불완전 적재 거부 → 복구 | 1 |
| 6~9 | acc1·M·Y·Add wide의 Golden을 각각 고의 변경 → 검출 | 0 |
| 10 | 별도 합성 overflow 상수로 중단 확인 | 0 |
| 11 | 계산 시작부터 500클록만 담은 VCD | 0 |

완료 5작업은 같은 실제 이미지·같은 Block을 재사용한 결과입니다. 서로 다른 다섯 이미지가 아닙니다.
작업마다 두 Conv acc·H·M·Add wide·Y를 각16,384개 비교합니다.
완료 뒤 A=X·B=Y·C=M도 전 원소를 검사해 Buffer 수명을 확인합니다.
Mode 0의 CSV 98,304행은 Python으로도 NPZ에서 얻은 기준과 전부 다시 비교합니다.
정수 후처리는 양수/음수 RNE·ReLU 유무·shift 0/31·64-bit 끝값·INT8 포화를 독립 Fraction 기준 2,000개와 비교합니다.

`results/residual_rtl/first500.vcd`를 GTKWave로 열면 READ_PAIR→MAC 반복을 따라갈 수 있습니다.
이는 별도 실행의 짧은 구간입니다. 전체 Block 일치 증거는 Scoreboard 로그와 CSV입니다.
Verilator는 `$dumpoff`를 무시하므로, 짧은 파형 실행 자체를 500클록에서 종료합니다.
[Verilator 공식 언어 문서](https://verilator.org/guide/latest/languages.html)를 참고하세요.

## 8. 결과와 제출

2026-11-02 [revision 841f6cf9의 전체 시험](https://github.com/tsi03048/resnet20-accel/actions/runs/41399400691)이 Verilator 5.020에서 통과했습니다.

| 검증 | 실제 결과 |
|---|---|
| 정상 완료 | 같은 실제 sample 0로 5 Block |
| Conv1/Conv2 누산 | 163,840개, 불일치 0 |
| H/M/Y code | 245,760개, 불일치 0 |
| Add의 64-bit wide | 81,920개, 불일치 0 |
| X 보존·B=Y·C=M | 245,760원소 검사 통과 |
| CSV의 NPZ 기준 재비교 | 98,304행 일치 |
| 후처리 독립 기준 | 2,000개 일치 |
| Reset 취소 | Conv1·Conv2·Y 대기 3위치 뒤 재적재·복구 통과 |
| 오류 검출 | 고의 Golden 오류 4종·불법 적재 14개·overflow 거부 |

벡터 출처·재생성·변조 거부를 포함한 Python 시험도 20개 통과했습니다.
대기 시험에서는 MAC 2,310,146에지·Conv 출력 32,768에지·Y 16,384에지·완료 응답 4에지를 실제로 관측했습니다.

최신 실행 판정은 `results/residual_rtl/summary.json`, 고정 실행 증거는 `results/residual_rtl_actual.json`에서 봅니다.
제출물은 실행 revision·패키지 identity·도구 버전·summary·mode별 로그·첫 두 위치 설명·미실행 범위입니다.

이번 단위는 L1.0 Identity입니다. Transition/Option A·9Block 연속 실행·전체 CNN RTL·합성/STA·보드는 후속입니다.
Verilator 시험과 4-state X/Z 전파 시험, 실제 FPGA RAM 추론 결과를 구분합니다.
[Stem→L1.0 연속 RTL](stem_residual_e2b_rtl.md)도 실제 전송·자동 시작·bit-exact 비교를 통과했습니다. 다음은 Transition의 서로 다른 Shape·shortcut 주소 검증입니다.

확인 질문: X를 중간에 덮어쓰면 무엇을 잃나요? M<0을 지우면 무엇이 바뀌나요? 마지막 y_valid가1이어도 ready=0이면 완료인가요?
답의 핵심: Skip 원본이 필요하며, 음수의 기여를 보존하고, 마지막 출력과 완료 응답의 수락까지 기다립니다.
