# E13-B. 실제 정수 Stem을 RTL로 실행하고 Golden과 비교하기

이번 목표는 **E2-B에서 고정한 상수와 첫 이미지로 Stem Conv를 실행해, 누산값과 출력 code가 모두 같은지 확인하는 것**이다.
먼저 [S0~S4](basic_track.md)와 [E2-B](e2b_integer_reference.md)를 진행한다. 작은 Conv가 익숙해진 뒤 이 선택 실습으로 넓힌다.

기존 E13의 진단용 `/4` 예제는 별도 버전이다. 여기서는 새 공개 구현 `rtl/stem_e2b_v1/`을 사용한다.
이 실습의 계산은 Stem 한 층이다. Residual·전체 CNN RTL·합성·배치배선·보드 실행은 후속 과제다.

## 1. 먼저 실행하기

**설치 없이 확인:** GitHub 저장소의 Actions → Basic track checks → `stem-real-integer`를 연다.
완료된 실행의 `stem-real-integer-evidence` artifact를 받으면 로그·CSV·부분 파형·요약을 확인할 수 있다.

**직접 실행:** Ubuntu 또는 Windows의 WSL Ubuntu에서 저장소 최상위로 이동한다. Python과 Icarus Verilog가 필요하다.

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv iverilog
python3 -m venv .venv
source .venv/bin/activate
python -m pip install numpy
bash tb/stem_e2b_v1/run.sh
```

PyTorch·GPU·CIFAR-10 다운로드·재학습은 이 RTL 실습에 필요 없다. 이미 동결한 실제 입력과 상수를 쓴다.
PowerShell에서 `bash`나 `iverilog`가 없으면 위 명령을 WSL 안에서 실행하거나 Actions를 이용한다.
Colab의 T4는 이 HDL 시뮬레이션을 가속하지 않는다.

정상 종료는 마지막 JSON의 `status: PASS`, `completed_jobs: 5`, 누산·출력 불일치 각각 0이다.
중간의 `EXPECTED_OUTPUT_MISMATCH`와 `EXPECTED_ACC_MISMATCH`는 오답을 의도적으로 넣어 실패 검출을 확인하는 시험이다.
그 두 실행의 실패를 스크립트가 확인한 뒤 전체 PASS를 판정한다. 개별 로그 한 줄만으로 성공을 판단하지 않는다.

## 2. 세 종류의 파일을 구분하기

| 파일 | 역할 | DUT에 적재하는가? |
|---|---|---|
| input.hex | 실제 Test sample 0의 정수 입력 3,072개 | 예 |
| weight.hex | 실제 Stem 정수 Weight 432개 | 예 |
| bias.hex, multiplier.hex, shift.hex | 출력 채널별 Bias·N·r, 각각 16개 | 예 |
| acc_expected.hex, output_expected.hex | 비교 기준인 누산·출력, 각각 16,384개 | 아니요. Testbench만 읽음 |
| constants.npz, sample0/tensors.npz | E2-B 전체 상수와 61경계 Golden | Python이 hex의 출처·내용을 재검증 |

위 파일은 `reference/e2b_v1/`에 있다. DUT는 `$readmemh`나 기대값을 갖지 않는다.
Testbench가 hex를 읽고 실제 loader 포트로 적재한 뒤, DUT가 내놓는 값과 기대값을 비교한다.
내부 신호를 읽는 부분은 Stall 동안 상태가 유지되는지 감시하는 용도이며 메모리에 값을 몰래 쓰지 않는다.

`tools.verify_stem_vectors`는 패키지 hash·Shape를 확인하고 NumPy로 61경계를 다시 계산한 다음 모든 hex word를 원본 배열과 대조한다.
hex는 ASCII·LF 줄바꿈·마지막 LF로 고정한다. Windows/Linux에서 같은 파일 hash가 되도록 exporter도 같은 바이트를 쓴다.
줄바꿈만 바꿔도 파일 hash 검사는 실패한다. 내용 변조 검사를 건너뛰지 않는다.

## 3. Shape와 주소를 손으로 따라가기

입력은 NCHW `[1,3,32,32]`, Weight는 OIHW `[16,3,3,3]`, 출력은 `[1,16,32,32]`다.
Stride=1, Padding=1이며 바깥 입력은 code 0이다. Zero-point가 0이므로 가능한 규칙이다.

```text
출력 주소 = oc*1024 + oy*32 + ox
항 번호 t = ci*9 + ky*3 + kx       (0..26)
iy = oy + ky - 1, ix = ox + kx - 1
입력 주소 = ci*1024 + iy*32 + ix   (이미지 안일 때만)
Weight 주소 = oc*27 + t
```

주소는 byte 주소가 아니라 **원소의 순번**이다. 8-bit hex는 두 자리, 32-bit hex는 여덟 자리다.
입력/Weight는 signed two's complement이며 Byte 순서를 뒤집지 않는다. Weight -128은 이 프로파일에서 사용하지 않는다.
출력 하나에 Padding 항도 포함해 27 MAC이므로 한 작업은 16,384 출력·442,368 MAC이다.

실제 첫 출력은 다음과 같다. 이 값은 다른 채널에 그대로 적용하는 상수가 아니다.

```text
곱의 합 = 411, Bias[0] = 11879
acc = 411 + 11879 = 12290
N[0] = 3519126, r[0] = 31
RNE(12290 * 3519126 / 2^31) = 20
ReLU와 [0,127] 포화 뒤 code = 20
```

단순 `/4`, 절삭 right shift, 음수에 무조건 half를 더하는 방식은 이 계약과 다르다.
RNE는 가장 가까운 정수로 반올림하되 정확한 중간값은 짝수로 간다: 2.5→2, 3.5→4, -2.5→-2, -3.5→-4.
64-bit로 `acc*N`을 만들고 RNE를 한 번 적용한 뒤 ReLU·포화한다.
후처리 RTL은 Python `Fraction` 기반 독립 기준 1,280개로 별도 비교한다. 음수·동점·r=0/31·포화를 포함한다.

## 4. 적재 → 시작 → 출력 수락

| cfg_kind | cfg_addr | cfg_data |
|---|---|---|
| 0: 입력 | 0..3071 | 하위 8-bit code, 상위 24-bit=0 |
| 1: Weight | 0..431 | 하위 8-bit code, 상위 24-bit=0, 0x80 거부 |
| 2: Bias | 0..15 | signed INT32 비트열 |
| 3: N | 0..15 | 비음수 signed INT32 |
| 4: r | 0..15 | 0..31 |

1. Reset 뒤 IDLE에서 `load_begin`을 한 클록 넣어 기존 적재 상태를 무효화한다.
2. `cfg_valid && cfg_ready`인 상승 에지마다 한 word를 적재한다. `cfg_addr`는 종류마다 다시 0부터다.
3. 서로 다른 주소가 모두 채워져야 `prepared=1`이다. 같은 주소를 두 번 써도 개수는 늘지 않는다.
4. `start_ready=1`일 때 `start`를 한 클록 넣는다. 적재와 시작을 같은 에지에 요청하지 않는다.
5. `y_valid && y_ready`인 상승 에지에서만 `y_addr/y_acc/y_code`를 수락한다.
6. 마지막 주소 16383을 수락하면 `done`이 한 클록 나온다. `busy=0`에서 재실행할 수 있다.

`cfg_ready=0`일 때는 적재가 수락되지 않는다. 이 RTL의 `load_error`는 **수락한 word 자체가 잘못된 경우** 한 클록 나온다.
미준비 또는 Busy 중 시작 요청은 `start_rejected`로 알려 준다.
Reset은 진행 중 작업을 취소하고 적재 상태도 무효화하므로 전체를 다시 적재해야 한다.
누산 범위를 벗어나면 `compute_error=1`로 작업을 중단하며 성공 `done`을 내지 않는다. `load_begin`이나 새 정상 시작/Reset으로 해제한다.

## 5. 파형과 회로 흐름

```text
IDLE → INIT(Bias/N/r 선택) → READ_PAIR(X/W 등록) → MAC
                                 ↑                 │
                                 └─ 27항 미완료 ──┘
27번째 MAC → REQUANT → STORE → 다음 출력 INIT / 마지막 출력 IDLE
```

`MAC`에서 `mac_ready=0`이면 항·누산·등록된 X/W를 유지한다.
`STORE`에서 `y_ready=0`이면 valid와 주소·누산·code를 유지한다.
한 MAC을 순차로 반복하는 교육용 엔진이므로 PE 배열의 처리량·BRAM 배치·DSP 사용량을 보여 주는 결과는 아니다.

`results/stem_rtl/first_window.vcd`는 계산 시작 후 첫 300클록만 담는다.
짧은 파형은 제어 학습용이며 전체 일치 증거는 Scoreboard 로그와 CSV다.
GTKWave를 별도로 설치한 경우 `gtkwave results/stem_rtl/first_window.vcd`로 연다.

## 6. 시험이 보장하는 범위

| Mode | 시험 | 완료 작업 수 |
|---|---|---|
| 0 | 실제 sample 0 두 번 연속 실행, 전체 출력 CSV | 2 |
| 1 | MAC/출력 Stall, payload hold, Busy 중 적재 차단·시작 거부 | 1 |
| 2 | 중간 Reset 취소, 미준비 시작 거부, 재적재·완료 | 1 |
| 3 | 첫 기대 code만 고의 변경 → 실패해야 함 | 0 |
| 4 | 첫 기대 acc만 고의 변경 → 실패해야 함 | 0 |
| 5 | 잘못된 종류/주소/값 8개 거부, 중복/불완전 적재 확인, 복구 | 1 |
| 6 | 별도 합성 overflow 입력 → compute_error, 출력·done 없음 | 0 |

완료한 다섯 작업은 **같은 실제 이미지와 같은 상수**다. 서로 다른 다섯 이미지 검증으로 표현하지 않는다.
총 81,920개 누산과 81,920개 출력 code를 RTL Scoreboard로 비교한다.
Mode 0의 CSV 32,768행은 Python이 NPZ Golden과 다시 전부 비교한다.
이 결과는 sample 0의 Stem과 해당 제어 시험을 확인한다. 다른 이미지·다른 층·전체 모델의 RTL 정확도는 후속 검증이다.

## 7. 결과와 제출

2026-11-02 [revision 5fef496f의 전체 자동 시험](https://github.com/tsi03048/resnet20-accel/actions/runs/41396748645)이 통과했다.
Icarus Verilog 12.0에서 완료 5작업·누산 81,920개·code 81,920개 불일치 0이다.
Mode 1에서 MAC 대기 196,608에지·출력 대기 16,384에지를 실제로 관측했다.
후처리 1,280개, 고의 누산/출력 오류 거부, 잘못된 적재 8개 거부, overflow 중단도 통과했다.
벡터 무결성·재해시한 숫자 변조·줄바꿈 변조 시험을 추가한 Python 16개 시험도 로컬에서 통과했다.

실행 요약은 `results/stem_rtl/summary.json`, 고정 실행의 기록은 `results/stem_rtl_actual.json`에서 확인한다.
로그·CSV·VCD는 Actions artifact에 보관하고 생성된 큰 결과는 Git에 넣지 않는다.
`source_sha256`는 실행한 RTL/Testbench 파일의 바이트 hash다. Windows에서 소스를 CRLF로 바꾸면 LF로 실행한 CI와 hash가 달라질 수 있다.

제출: 실행 revision·패키지 identity·도구 버전·전체 summary·mode별 로그·첫 출력 손계산·Stall/Reset 설명·미실행 범위를 남긴다.
연습 질문: code가 우연히 같아도 acc가 다르면 통과인가? Padding 항의 X는 어디서 오는가? y_valid만 보고 출력 수를 세면 왜 틀리는가?
답의 핵심은 누산도 일치해야 하며, Padding은 0이고, 출력은 valid와 ready가 함께 1일 때만 수락한다는 것이다.

다음 실습인 [실제 Identity Block L1.0](residual_e2b_rtl.md)도 Main/Skip 보존·Add 단위 정렬·bit-exact 비교를 통과했다.
Stem의 통과 기록을 유지한 별도 버전·시험이며, Stem→Block 연속 실행은 후속 통합 검증이다.
