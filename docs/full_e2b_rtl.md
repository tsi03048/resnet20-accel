# E8-B. 실제 정수 전체 ResNet-20 RTL 따라하기

작은 Conv → Stem → Identity Block → Transition을 읽었다면 마지막으로 모든 단계를 이어봅니다. **입력 사진의 정수 3,072개와 실제 계수만 회로에 넣고, Stem부터 9개 Block·GAP·FC까지 회로가 계산합니다.** Golden은 테스트 장치가 비교할 때만 읽습니다.

이 실습은 S5 선택 확장입니다. 처음 배우는 학생은 [전체 흐름](learning/theory_first.md)과 [S5](learning/S5.md)의 앞 단계를 먼저 읽으세요. 기본 작은 Conv 과제를 전체 모델 과제로 바꾸지는 않습니다.

## 1. 무엇을 잇나요?

| 작업 번호 | 계산 | 출력 크기 |
| --- | --- | --- |
| 0 | Stem | 16×32×32 |
| 1~9 | Stage 1의 3개 Block | 16×32×32 |
| 10~18 | Stage 2의 3개 Block, 첫 Conv stride2 | 32×16×16 |
| 19~27 | Stage 3의 3개 Block, 첫 Conv stride2 | 64×8×8 |
| 28 | GAP: 채널별 공간 평균 | 64개 |
| 29 | FC: 후보별 점수 | signed INT32 10개 |

총 19 Conv + 9 Add + GAP + FC = 30작업입니다. 각 작업의 출력뿐 아니라 Conv/FC 누산값, Add의 Skip, GAP의 합도 봅니다. 입력 1경계 + Conv 38경계 + Add 18경계 + GAP 2경계 + FC 2경계 = **61경계, 한 번에 552,084원소**입니다. Add의 넓은 곱·합과 실제 Skip 주소는 추가로 검사합니다.

한 이미지에서 Conv/FC는 40,551,040 MAC, GAP는 4,096번의 합산을 수행합니다. MAC은 곱한 값을 중간 합에 더하는 한 번의 동작입니다. 출력 이벤트는 274,506개입니다. 이벤트 수·경계 수·원소 수는 서로 다릅니다.

## 2. 앞단 결과를 다시 넣지 않습니다

`rtl/full_e2b_v1/full_model.sv`는 고정 작업표를 따라 하나의 순차 계산 경로를 재사용하는 새 전체 모델 구현입니다. 앞 실습의 고정 크기 모듈을 9번 복사한 구조가 아닙니다. 이전 단위 모듈과 검증 기록도 유지합니다.

Feature bank는 중간 숫자를 보관하는 저장 공간입니다. 16 KiB짜리 세 bank에 X(블록 입력), H(Conv1 출력), M(Conv2 출력)을 나눠 둡니다. Conv2가 H를 모두 읽은 뒤에 Add가 그 공간을 Y로 재사용합니다.

| 계산 | 읽기 | 쓰기 |
| --- | --- | --- |
| 입력 로딩 | Host | bank 0 |
| Stem | bank 0 | bank 1 |
| L1.0 Conv1 | bank 1의 X | bank 2의 H |
| L1.0 Conv2 | bank 2의 H | bank 0의 M |
| L1.0 Add | bank 0의 M + bank 1의 X | bank 2의 Y |
| 다음 Block | 직전 Y가 새 X | 남은 bank를 회전 |
| L3.2 이후 GAP | bank 1 | bank 2에 64개 |
| FC | bank 2 | 별도 signed INT32 score 배열 10개 |

테스트는 매 작업의 시작에서 입력 bank 전체를 앞 작업의 Golden과 다시 비교합니다. 테스트 장치가 회로의 중간 bank를 채우는 코드는 없습니다. 회로의 `$readmemh`도 없습니다. 파일 로딩은 테스트 장치의 역할입니다.

이 배열 선언과 곱셈식을 ZedBoard의 실제 BRAM·DSP 배치로 검증한 것은 아닙니다. 전체 Weight payload만 268,336 bytes이고 feature 외에 bias·계수·상태가 필요합니다. 합성·외부 메모리·타이밍 설계는 다음 범위입니다.

## 3. GAP와 FC를 실제 숫자로 읽기

GAP는 64개 채널을 유지합니다. 각 채널의 8×8=64개 정수를 INT32로 합친 뒤 눈금을 바꿉니다. E2-B v1의 계수에는 **평균의 /64가 이미 포함**되어 있습니다.

```text
gap[c] = clip_0_127(RNE(sum64[c] * 141471614 / 2^31))
sample 0의 첫 네 채널:
sum64 = [433, 23, 612, 64]
gap   = [29,   2,  40,  4]
```

먼저 정수로 /64를 해서 반올림하거나 계수 적용 뒤 /64를 한 번 더 하면 다른 함수가 됩니다. RNE는 가장 가까운 정수로 반올림하되 정확히 절반이면 짝수를 고르는 규칙입니다. 넓은 곱은 signed INT64입니다.

FC는 GAP의 64개를 각 후보의 Weight 64개와 곱해 INT32로 누산합니다. Bias를 한 번 넣고 후보별 N/r로 공통 눈금 `2^-16`의 signed INT32 점수로 바꿉니다. FC에는 ReLU를 넣거나 INT8로 자르지 않습니다.

```text
sample 0, class 0:
bias = 402
64항 누산 후 acc = -12117
N = 2115654736, r = 26
score = RNE(-12117 * 2115654736 / 2^26) = -381997
```

모든 후보의 score가 같은 눈금이므로 가장 큰 정수를 고릅니다. 같은 최대값이면 가장 작은 index를 고릅니다. 서로 눈금이 다른 FC raw acc를 그대로 argmax하면 안 됩니다.

## 4. 적재 → 시작 → 결과 소비

1. Reset 후 `load_begin`으로 새 적재를 시작합니다.
2. `cfg_valid && cfg_ready`일 때만 한 단어를 씁니다. kind별 주소는 0부터 빈틈 없이 증가해야 합니다.
3. 입력 3,072개, Weight 268,336개, bias/N/r 각각 698개가 채워지면 `prepared=1`입니다.
4. `start && start_ready` 한 번으로 30작업을 자동 실행합니다.
5. `rsp_valid`에서 점수 10개와 `prediction`이 준비됩니다. `rsp_ready`로 결과를 소비하면 `done`이 한 번 올라옵니다.
6. 다음 이미지에는 `load_begin`부터 다시 적재합니다. 실행 중 bank 0도 재사용되므로 적재 없이 start만 반복할 수 없습니다.

| cfg_kind | 내용 | 규칙 |
| --- | --- | --- |
| 0 | 입력 INT8 | 주소 0~3071, byte를 32bit 하위 8bit에 넣고 상위 24bit는 0 |
| 1 | Weight INT8 | 주소 0~268335, 같은 byte 포장, -128은 거부 |
| 2 | bias INT32 | 주소 0~697, signed 32bit의 bit pattern |
| 3 | N INT32 | 주소 0~697, 0 이상 |
| 4 | r | 주소 0~697, 0~31 |

예를 들어 -1 입력은 `000000ff`로 전달합니다. `ffffffff`는 입력 byte 규약에 맞지 않습니다. 중복·순서 누락·범위 밖·잘못된 kind는 거부합니다. 앞 단위 실습과 달리 이 전체 모델 loader는 순차 적재를 강제합니다. 실행 중 적재 요청과 start도 작업을 바꾸지 않습니다.

Stall은 진행을 잠깐 기다리는 것입니다. `compute_ready=0`이면 MAC의 중간 합과 항 번호를 유지합니다. `trace_ready=0`이면 관측 출력과 bank 쓰기를 유지합니다. `rsp_ready=0`이면 완료 결과를 유지합니다. Reset은 취소이므로 중간 숫자가 메모리에 남아 있어도 준비 상태를 모두 지우고 새 적재를 요구합니다.

## 5. 직접 재실행

Ubuntu/WSL에 Python 3.11 이상, NumPy, Verilator 5.020 이상, C++ 컴파일러와 make가 필요합니다. 저장소 루트에서 실행합니다. Windows PowerShell에서 bash를 그대로 실행하지 말고 Ubuntu/WSL 터미널을 쓰세요. 회로 시험만 다시 할 때는 PyTorch·CIFAR-10 다운로드·T4 GPU가 필요 없습니다.

```bash
python -m pip install numpy
sudo apt-get update
sudo apt-get install -y verilator g++ make
bash tb/full_e2b_v1/run.sh
```

이 명령은 기준 파일 생성·해시/의미 검사 → RTL 빌드 → 정상 0→1→0 → Stall → Reset/재실행 → 오류 검출 → CSV 재대조를 수행합니다. 실행 시간이 짧은 단위 실습보다 길어집니다. `.github/workflows/full_model.yml`은 빌드를 한 번 하고 서로 다른 시험을 나눠 실행합니다.

관심 있는 시험만 다시 볼 수도 있습니다. 빌드 후 각 명령을 선택하세요.

```bash
bash tb/full_e2b_v1/run.sh build
bash tb/full_e2b_v1/run.sh case 0
bash tb/full_e2b_v1/run.sh case 1
bash tb/full_e2b_v1/run.sh case 2
bash tb/full_e2b_v1/run.sh case negative
bash tb/full_e2b_v1/run.sh summary
```

`summary`는 모든 시험 로그가 있어야 통과합니다. 파일에 틀린 값이 있는데 해시만 다시 계산해도 의미 검사가 거부합니다. 기준 상수나 Golden을 RTL 결과에 맞춰 바꾸지 마세요.

| mode | 시험 | 기대 완료 |
| --- | --- | --- |
| 0 | sample 0 → 1 → 0 | 3회, 예측 3→8→3 |
| 1 | MAC·trace·결과 Stall, busy 적재/시작 거부, 오래된 입력 재시작 거부 | sample 0 1회 |
| 2 | Stem 실행 중·Transition 실행 중·최종 응답 대기 중 Reset, 완전 재적재 | sample 1 1회 |
| 6~9 | Stem code·Option A Skip·GAP 합·FC score Golden을 한 bit 변경 | 각 시험이 지정된 mismatch로 실패해야 통과 |
| 10 | loader 형식·주소·누락 거부 | 잘못된 요청 10개 거부 |
| 11 | 인공 과대 bias/입력으로 INT32 누산 overflow | fault=1, 결과 공개 없음, Reset 정리 |

고의 오류 시험 로그의 실패 문구는 검출기의 정상 동작입니다. 이외의 오류나 단순 timeout을 성공으로 세지 않습니다. 별도로 Fraction 기반 2,000개 벡터로 signed RNE/포화 3종을 검사하고, argmax는 음수·INT32 양끝·동점·유지·초기화를 검사합니다.

## 6. 기대 점수와 실행 증거

**2026-11-02 실제 RTL 검증 통과.** [실행 revision 60f37028, 정상·Stall·Reset·오류 검출·CSV 재대조](https://github.com/tsi03048/resnet20-accel/actions/runs/41409298942)에서 모든 시험이 통과했습니다. source와 원본 artifact의 해시를 확인한 뒤 로컬에서도 274,506행을 재대조했습니다. 아래 점수는 기대값과 실제 RTL이 모두 일치한 값입니다. [고정 결과](../results/full_rtl_actual.json) · [실행 식별·원본 artifact 정보](../results/full_rtl_evidence.json) · [실행 로그](../results/full_rtl_execution.log)

Stall 완료 실행은 MAC 대기 13,424,208회, trace 대기 274,506회, 결과 대기 6회를 포함합니다. 각 대기에서 값 유지 검사가 통과했습니다. 정상 실행도 결과 읽기를 위한 짧은 응답 대기를 포함합니다.

고정된 실제 CIFAR-10 Test 0은 cat(index 3), Test 1은 ship(index 8)입니다. 새 calibration·재학습은 하지 않았습니다. sample 1 입력은 원본 Arrow/RGB/전처리/정수 입력 해시를 `sample1_source.json`에 보존했습니다. 같은 전처리로 만든 sample 0도 기존 입력과 일치하는지 확인했습니다.

원본 Test Arrow가 있는 환경에서는 `python -m tools.verify_full_inputs_from_arrow <Test-Arrow-경로>`로 전처리부터 두 입력을 다시 확인할 수 있습니다. 이 선택 검사에는 기존 학습 환경의 PyTorch·torchvision·datasets가 필요하며 파일을 자동 다운로드하지 않습니다. RTL만 재실행할 때는 동봉된 정수 입력을 씁니다.

| class | sample 0 score | sample 1 score |
| --- | --- | --- |
| 0 airplane | -381997 | 375818 |
| 1 automobile | -36909 | 759555 |
| 2 bird | 46541 | -571137 |
| 3 cat | 1586887 | -422553 |
| 4 deer | -259757 | -786112 |
| 5 dog | 306431 | -518376 |
| 6 frog | 35286 | -400169 |
| 7 horse | -351394 | -532279 |
| 8 ship | -276301 | 2082934 |
| 9 truck | -666530 | 15190 |

결과 요약은 `results/full_rtl_actual.json`, 원본 로그와 첫 정상 sample 0의 전체 CSV는 `results/full_rtl/`에 생성됩니다. CSV의 274,506행도 Python이 정수 Golden과 다시 비교합니다. NumPy/PyTorch 정수 구현 간 두 입력의 모든 경계 비교는 `tests/test_full_vectors.py`에 있습니다.

완료 5회는 서로 다른 이미지 5장을 뜻하지 않습니다. 실제 이미지는 2종이며 정상 3회 + Stall 1회 + Reset 회복 1회입니다. 회복 전에 취소한 작업은 완료 합계에 더하지 않습니다. 다섯 완료가 모두 통과하면 경계 원소 비교는 2,760,420개, 출력 이벤트는 1,372,530개입니다.

소프트웨어 Test 전체 91.70%와 이 RTL의 두 이미지 비교는 범위가 다릅니다. 이 실습은 10,000장 RTL 정확도, 실제 FPGA 합성·배치배선·보드·FPS 검증을 포함하지 않습니다.

## 7. 직접 설명하고 제출하기

1. L1.0 Add 전에 X bank를 덮어쓰면 어떤 경계가 먼저 틀릴까요?
2. `433`을 먼저 정수로 64로 나눈 뒤 계수를 적용하면 왜 기준과 달라지나요?
3. FC raw acc와 공통 눈금 score 중 무엇을 비교해야 하나요?
4. 0→0 대신 0→1→0을 실행하면 어떤 오류를 찾기 쉬운가요?
5. Stall과 Reset 뒤 다시 적재해야 하는 경우는 어떻게 다른가요?

자신의 날짜·source revision·명령·패키지 해시·정상 예측 순서·61경계 불일치 수·Stall 횟수·Reset 위치·고의 오류 검출 결과를 남기세요. 배포된 결과를 읽었다면 ‘기준 결과 열람’, 직접 실행했다면 ‘재실행’으로 구분합니다. 실행하지 못한 항목은 NOT_RUN으로 적습니다.
