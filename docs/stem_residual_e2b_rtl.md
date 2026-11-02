# E14-C. Stem에서 Residual Block까지 RTL로 연속 실행하기

이번 목표는 **시작 한 번으로 Stem → 첫 Identity Block L1.0를 실행하고, 실제 계산한 중간값과 최종값을 정수 Golden과 비교하는 것**입니다.
[Stem 단위 실습](stem_e2b_rtl.md)과 [Residual 단위 실습](residual_e2b_rtl.md)을 먼저 봅니다. 기초 계산·회로가 낯설면 기본 이론을 읽고 S0~S4부터 진행합니다.

이전에는 저장한 Stem 출력을 Block 입력으로 적재했습니다. 이번에는 Stem RTL이 계산한 출력이 연결부를 통해 Block의 X 메모리에 기록됩니다.
Testbench는 그 전송을 관찰하며, Block의 X를 외부에서 미리 넣는 요청은 거부합니다.

## 1. 먼저 실행하기

설치 없이 확인하려면 GitHub **Actions → Actual integer Stem to Residual → stem-residual-real-integer**를 엽니다.
완료된 실행의 `stem-residual-real-integer-evidence`에 전체 로그·CSV·짧은 파형·요약이 있습니다.

직접 실행하려면 Ubuntu 24.04 또는 Windows의 WSL Ubuntu에서 저장소 최상위로 이동합니다.

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv build-essential verilator
python3 -m venv .venv
source .venv/bin/activate
python -m pip install numpy
bash tb/stem_residual_e2b_v1/run.sh
```

이 실습에는 GPU·데이터 다운로드·재학습이 필요하지 않습니다. NumPy·Verilator·C++ 빌드 도구를 사용합니다.
성공하면 마지막 JSON에 `status: PASS`가 나옵니다. 고의 mismatch 시험은 해당 실행이 실패해야 전체 시험이 통과합니다.
`TRACE_WINDOW_ONLY`는 짧은 파형 실행이며 정상 완료 수에 포함하지 않습니다.

## 2. 무엇이 연결되었나

```text
Host: 이미지 정수 입력 + Stem 상수 + Block 상수 적재
                         ↓ start 한 번
Stem RTL: [1,3,32,32] → [1,16,32,32]
                         ↓ 실제 valid/ready 전송 16,384회
Block X 메모리: 수락한 Stem code를 같은 주소에 저장
                         ↓ 전체 적재·Stem 완료 확인 후 자동 시작
Block RTL: Conv1 → H → Conv2 → M → X와 단위 정렬 Add → Y
                         ↓ 마지막 Y 수락
                    완료 응답 → done
```

`rtl/stem_residual_e2b_v1/stem_residual.sv`가 연결과 시작 순서를 관리합니다.
기존 Stem·Residual 수치 코어 네 파일은 그대로 재사용합니다. 같은 클록에서 Stem 전체를 전달한 뒤 Block을 실행하는 구조입니다.
두 계층을 동시에 겹쳐 실행하거나 서로 다른 클록을 연결하는 설계는 후속입니다.

한 체인의 MAC은 Stem 442,368 + Block 4,718,592 = **5,160,960회**입니다. 이 값은 실제 FPGA 클록 수나 FPS가 아닙니다.
Block 내부의 X 보존·Conv2 음수 유지·64-bit Add 후 한 번 RNE 규칙은 E14-B와 같습니다.

## 3. 먼저 준비할 것과 실행 중 생기는 것

| 종류 | 누가 준비하나 | 준비 완료 시점 |
|---|---|---|
| Stem 이미지 입력·Weight/Bias/N/Shift | Host 또는 Testbench의 loader | start 전 |
| Block의 W1/W2·B1/B2·N1/N2·Shift·Add 계수 | Host 또는 Testbench의 loader | start 전 |
| Block X | 실제 Stem RTL 출력 | Stem 실행 중 |
| H/M/Y | Block RTL | Block 실행 중 |
| 기대 acc/code/wide | Testbench만 읽는 Golden | 비교용, DUT에 적재하지 않음 |

상위 `prepared=1`은 **외부에서 준비할 입력·상수가 모두 있고 새 작업을 시작할 수 있다**는 뜻입니다.
이 시점에 Block X의 유효 개수는0입니다. 내부 Block의 prepared는 아직0입니다.
연결부가16,384개를 전부 기록한 뒤 내부 Block prepared가1이 되어야 자동 시작합니다.
같은 prepared라는 이름도 어느 모듈의 경계인지 확인해야 합니다.

## 4. 한 값을 어떻게 넘기는가

```text
bridge_valid = Stem이 보낼 값을 보유하고 있음
bridge_ready = Block loader가 받을 수 있고 link_ready=1이며 주소/개수가 맞음
fire = bridge_valid && bridge_ready
```

수락 에지에서 다음 사건이 함께 일어납니다.

1. Stem이 해당 출력을 소비합니다.
2. Block loader가 `kind=0`, 같은 원소 주소, 실제 Stem code를 기록합니다.
3. 연결부 전송 개수와 Block 입력의 유효 주소 개수가 하나씩 늘어납니다.

`ready=0`이면 주소·acc·code를 유지하고 두 개수도 늘지 않습니다.
`link_ready`는 연결 대기 시험을 위한 제어 입력입니다. 정상 사용에서는1로 둡니다.
연결부는 주소가0부터16,383까지 순서대로인지, 두 모듈의 수락 개수가 같은지도 검사합니다.

실제 첫 전송은 Stem `acc=12290, code=20, address=0`입니다.
그 code20이 Block의 Skip 원본 X[0]가 됩니다. Block의 첫 출력은 H=23, M=3, Skip=20, Y=18입니다.
단지 마지막 class나 checksum만 확인하는 것이 아니라 이 경계를 전 원소 비교합니다.

## 5. 적재·시작·완료 순서

`cfg_target=0`은 Stem, `cfg_target=1`은 Block 상수를 선택합니다. 각 종류의 값 범위는 앞선 단위 실습과 같습니다.

| target | 허용 kind | 의미 |
|---|---|---|
| 0 | 0..4 | 이미지 입력·Stem Weight·Bias·N·Shift |
| 1 | 1..9 | Block W1/W2·B1/B2·N1/N2·Shift·Add 계수 |
| 1 | 0 | 외부 Block X 적재: 거부 |

1. IDLE에서 `load_begin`을 한 클록 넣습니다. 두 코어의 적재 상태와 이전 연결 개수를 무효화합니다.
2. 이미지 입력과 두 모듈의 상수를 loader로 적재합니다. `cfg_valid && cfg_ready` 상승 에지에서만 수락됩니다.
3. 상위 `start_ready=1`일 때 `start`를 한 클록 넣습니다.
4. 이후 중간 시작 요청 없이 자동으로 Stem 계산·연결 전송·Block 실행을 진행합니다.
5. 최종 Y는 `y_valid && y_ready`에서 수락합니다. 마지막 Y가 수락된 뒤 완료 응답이 나옵니다.
6. `rsp_valid && rsp_ready`로 완료 응답을 수락하면 `done`이 한 클록 나옵니다.

다음 이미지에는 `load_begin`부터 전체 입력·상수를 다시 적재합니다. 현재 버전은 작업마다 재준비하는 교육용 기준입니다.
이전 프레임의 준비 상태로 곧바로 다시 시작하는 요청은 거부합니다. 상수 유지·이미지만 교체하는 최적화는 별도 계약이 필요합니다.
Busy 동안 Host 적재와 재시작도 수락하지 않습니다.

## 6. 같은 값만 반복해서 맞는 문제를 피하기

정상 반복 시험은 **실제 sample 0 → 정수 입력이 모두0인 합성 프레임 → 실제 sample 0** 순서입니다.
합성 입력은 학습된 실제 상수를 그대로 쓰는 제어 시험입니다. 실제 CIFAR 이미지나 정확도 평가 이미지로 세지 않습니다.
여기서0은 정수 core 입력 code이며, 원본 RGB의 검은 사진이라는 뜻은 아닙니다.

이 입력 변경으로 Stem code10,755개·H9,030개·M14,065개·Y11,948개가 달라집니다.
이전 프레임의 X나 Y를 그대로 재사용하면 비교에 실패해야 합니다. 합성 입력의 기준은 NumPy와 Torch의 별도 정수 경로로도 비교합니다.

`tools/chain_vectors.py`는 원래 패키지 hash와 실제 sample 0의61경계 재현을 확인하고 연결 시험 hex를 만듭니다.
고정 `reference/e2b_v1/chain_vectors/manifest.json`과 바이트 hash·Shape·값을 대조합니다.
Stem Golden과 Block 입력 Golden이 같은지도 확인합니다. 이 파일들은 Testbench의 비교 기준이며 DUT의 연결 데이터는 RTL 계산 결과입니다.

## 7. 대기·취소·오류를 읽는 법

| Mode | 확인하는 것 | 정상 완료 체인 |
|---|---|---|
| 0 | 실제 → 합성0 → 실제, 모든 경계 CSV | 3 |
| 1 | 두 MAC·연결·Conv·Y·완료 응답 대기, Busy 요청 거부 | 1 |
| 2 | 연결 대기 중·Block Conv2 중·Y 대기 중 Reset → 재적재·완료 | 1 |
| 5 | Host Block-X 적재·주소 잘림·잘못된 종류/상수 등8개 거부 → 완료 | 1 |
| 6~9 | 연결 code·M·Y·Add wide Golden의 고의 오류 검출 | 0 |
| 10, 11 | Stem/Block overflow를 상위 fault로 전달, 성공 응답 억제 | 0 |
| 15 | 연결부 근처500클록만 기록하는 별도 파형 | 0 |

Reset은 두 코어와 연결 상태를 함께 취소하고 prepared를 내립니다. 부분 입력을 다음 작업에 쓰지 않도록 전체를 다시 적재합니다.
`fault_code=1`은 Stem 연산 오류,2는 Block 연산 오류,3은 연결 주소/개수 계약 위반입니다.
오류 상태에서는 성공 응답·새 시작·Host 적재를 막습니다. Reset 또는 `load_begin`으로 취소한 뒤 다시 준비합니다.
overflow 시험은 오류 해제 뒤 prepared까지 재준비를 확인하며, 그 시험 안의 전체 계산 재실행은 완료 수에 넣지 않습니다.

`results/stem_residual_rtl/first_bridge.vcd`는 초기 연결 전송 근처의500클록만 담습니다.
GTKWave에서 bridge_valid/ready·bridge_count·block_input_count와 실제 code를 함께 봅니다.
전체 일치 증거는 Scoreboard 로그와 CSV입니다. 짧은 파형 실행은 완료 체인으로 세지 않습니다.

## 8. 결과와 제출

2026-11-02 [revision b9bf7d50의 전체 회귀](https://github.com/tsi03048/resnet20-accel/actions/runs/41402525320)가 Verilator 5.020에서 통과했습니다.
정상 완료6체인, 그중 실제 sample 0는5회·합성0은1회이며 모든 경계 불일치0입니다.

| 완료분의 비교 | 실제 sample 0, 5회 | 합성0, 1회 | 합계 |
|---|---|---|---|
| Stem→Block 전송 | 81,920 | 16,384 | 98,304 |
| 세 Conv 누산값 | 245,760 | 49,152 | 294,912 |
| Stem/H/M/Y code | 327,680 | 65,536 | 393,216 |
| Add wide | 81,920 | 16,384 | 98,304 |

완료마다 실제 연결 전송16,384개, Stem/Conv1/Conv2 acc49,152개, Stem/H/M/Y code65,536개, Add wide16,384개를 비교합니다.
종료 후 Block의 X가 실제 전달값과 같은지, B=Y·C=M인지도 전부 검사합니다.
정상 CSV196,608행을 Python으로 전부 재비교했고, 내려받은 결과도 로컬에서 다시 검산했습니다.
Python 시험24개도 통과했습니다. 합성 프레임의9개 경계는 NumPy/Torch 별도 경로로 일치했습니다.
단위 시험 때 사용한 수치 코어 네 파일의 hash가 이번 실행과 같은지도 확인했습니다.

고정 실행 증거는 `results/stem_residual_rtl_actual.json`, 재실행 요약은 `results/stem_residual_rtl/summary.json`입니다.
제출물은 실행 revision·package identity·도구 버전·summary·mode별 로그·첫 전송과 마지막 완료 설명·미실행 범위입니다.

이번 완료 범위는 같은 클록의 Stem→첫 Identity Block 연속 실행입니다. Transition·9Block·전체 CNN RTL·AXI/DMA·합성/STA·보드는 후속입니다.
Verilator 결과를4-state X/Z 검증이나 FPGA 메모리 추론·실측 결과와 구분합니다.

확인 질문: Host의 Block-X 적재를 왜 막나요? Block 준비 개수가 전부 차기 전에 시작하면 어떻게 되나요? valid만 보고 전송 개수를 세면 왜 틀리나요?
답의 핵심: 실제 RTL 경로를 시험하기 위해서이며, 완전한 입력과 적절한 valid/ready 수락이 필요합니다.

다음 단위인 [실제 Transition L2.0·L3.0](transition_e2b_rtl.md)도 stride2·Option A의 주소/수치 비교를 통과했습니다. 여기의 Stem→L1.0 연속 시험과는 별도 단위이며 모든 중간 Block을 이은 전체 모델 실행은 후속입니다.
