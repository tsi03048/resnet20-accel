# E2-B — 실제 정수 기준을 만들고 같은 값인지 확인하기

E2-A에서는 정수 눈금으로 반올림한 값을 다시 실수로 풀어 계산했고 Bias도 FP32였다.
E2-B에서는 **정수 Weight·정수 Bias·정수 계수로 Conv부터 최종 점수까지 계산**한다.
이 결과가 앞으로 RTL이 따라야 할 Golden이다. 소프트웨어끼리 맞는 것과 실제 RTL 검증은 구분한다.

## 1. 처음이라면: 데이터 다운로드 없이 한 장 재실행

저장소 최상위에서 다음을 실행한다. 이 단계는 NumPy만 필요하다.

```sh
python -m pip install numpy
python -m quant.replay_e2b --backend numpy
```

정상 결과는 `PASS`, `tensor_count: 61`, `compared_elements: 552084`, `prediction: 3`, `class_name: cat`이다.
배포한 실제 상수와 실제 Test sample 0의 정수 입력을 사용한다. 새로 학습하거나 상수를 선택하지 않는다.
`reference/e2b_v1/`의 패키지·Golden hash와 Shape를 확인한 뒤 61개 경계를 모두 비교한다.

실패 메시지의 파일·Tensor 이름부터 확인한다. 파일 hash가 다르면 숫자 계산을 시작하지 않는다.
`--backend torch`는 별도 구현으로 같은 검사를 한다. 이때 PyTorch가 필요하다.

## 2. 세 가지 기준은 무엇이 다른가?

| 기준 | 계산 | 확인하는 것 |
|---|---|---|
| FP32 | 원본 학습 모델 | 변환 전 분류 정확도 |
| E2-A fake-quant | 정수 눈금을 모사하되 FP32 계산·Bias 유지 | 정수화 후보의 품질 탐색 |
| E2-B | 정수 Weight/Bias·누산·N/Shift·RNE | RTL과 비교할 실제 정수 함수 |

E2-B가 E2-A와 모든 code까지 같아야 하는 것은 아니다. Bias 정수화·정수 계수 근사·입력 양자화·FC 점수 표현이 추가된다.
반면 같은 E2-B 계약을 구현한 RTL은 유효 code마다 정확히 같아야 한다.

## 3. 숫자 계약 v1

프로파일 이름은 `RESNET20_SIGNED_MINMAX_RNE_V1`이다. 기준 모델은 ResNet-20 CIFAR Option A, 19 Conv·9 Add·GAP·FC의 30작업이다.
기존 signed/minmax 채택과 Train 1,000장 보정 범위를 고정한다. Test로 범위나 계수를 다시 고르지 않는다.

| 항목 | 정확한 규칙 |
|---|---|
| 전처리 | 기존 FP32 Normalize. Host에서 수행 |
| 입력 code | 전처리 FP32 값을 binary64로 옮겨 `RNE(x/sx)`, [-128,127] 포화. 여기부터 정수 core |
| Weight | 출력 채널별 signed [-127,127], OIHW. 고정 BN Folding 뒤 정수화 |
| Activation | Tensor별 signed [-128,127], Zero-point=0. ReLU 출력은 [0,127] |
| Bias | 채널마다 `RNE(b/(sx*sw))`, INT32 |
| Conv/FC 누산 | `sum(qx*qw)+qb`. Bias는 출력마다 한 번 |
| Requant | `RNE(acc*N/2^r)` 한 번. 필요한 ReLU와 포화 적용 |
| 계수 | N은 비음수 signed INT32, r=0..31. 표현 가능한 가장 큰 r에서 최근접 짝수 N 선택 |
| Conv2 | ReLU를 적용하지 않고 정수화·포화한 Main code를 Add에 전달 |
| Residual | Main·Skip을 공통 분모로 환산해 넓게 더한 뒤 RNE 한 번, ReLU·포화 |
| Option A | 공간 ::2, 앞뒤 Channel 0 추가. 현재 z=0이므로 code 0 |
| GAP | 64개 code를 넓게 합한 뒤 `/64`와 Scale 변환을 한 계수로 반영, RNE 한 번 |
| FC 점수 | 모든 클래스가 공통 `2^-16` Scale, INT32 code, ReLU 없음 |
| Argmax | 공통 양수 Scale이므로 code끼리 비교. 동점은 가장 작은 Index |

실수 Scale과 Weight 변환은 export 단계에만 필요하다. 정수 core는 Scale 곱셈을 실행하지 않고 저장한 N/Shift를 쓴다.
소프트웨어는 INT64로 계산해 overflow를 확인하지만 계약상 Conv/FC 누산은 INT32다.
채널별 `abs(bias)+128*sum(abs(weight))`를 계산해 모든 누산 prefix가 INT32에 들어감을 확인한다.
이 패키지의 최대 보수적 누산 상한은 2,930,781이다. N을 곱하는 중간값은 INT64 범위를 검사한다.
이는 FPGA 자원·속도·전력 결과가 아니다.

## 4. 작은 수치로 먼저 이해하기

1. **Bias 단위:** sx=0.1, sw=0.2이면 누산 한 칸은 0.02다. Bias=0.3은 code 15로 더한다.
2. **RNE 동점:** 2.5→2, 3.5→4, -2.5→-2, -3.5→-4. 단순 right shift는 이 규칙과 다르다.
3. **Residual 단위:** Main code8·Scale1/8과 Skip code4·Scale1/4는 각각 실수1이다. 출력 Scale1/8이면 합 code16이다.
4. **한 번 반올림:** 두 경로를 각각 반올림하고 더하는 함수와, 넓게 더한 뒤 한 번 반올림하는 함수는 다를 수 있다. v1은 후자다.

실제 sample 0의 Stem 첫 출력은 다음과 같다.

```text
Conv 곱의 합 = 411
정수 Bias = 11879
acc = 12290
N = 3519126, r = 31
RNE(12290 * 3519126 / 2^31) = 20
ReLU·INT8 포화 뒤 출력 code = 20
```

`reference/e2b_v1/stem_vectors/`의 `bias.hex`, `multiplier.hex`, `shift.hex`, `acc_expected.hex`, `output_expected.hex`에서 확인한다.
주소 0의 값이다. 입력·Weight는 NCHW/OIHW 순서이며 한 줄이 한 원소의 two's-complement hex word다.
8-bit 원소는 두 자리, 32-bit 원소는 여덟 자리다. Byte 순서를 임의로 뒤집지 않는다.

## 5. 상수부터 다시 만들고 전체 평가하기

전체 실행은 PyTorch·Torchvision·NumPy·datasets가 필요하다. Colab 노트북을 권장한다.
E2-B의 현재 Torch 정수 backend는 **CPU**를 사용한다. T4 사용 여부가 이 실습을 GPU INT8 가속으로 만들지는 않는다.

```sh
python -m pip install -r requirements.txt
python -m quant.run_e2b --limit 10000 --audit 8 --batch-size 32
```

실행 순서는 다음과 같다.

1. 배포한 `source_e2a_report.json`·`source_e2a_selection.json`을 읽는다. 사용자가 직전에 돌린 E2-A 결과를 조용히 덮어쓰거나 재선택하지 않는다.
2. 고정 commit·checkpoint SHA256·Strict Load를 확인한다. 새 학습은 하지 않는다.
3. 정수 Weight·Bias·N·Shift·보수적 범위를 생성하고 패키지로 저장한다.
4. 파일을 다시 읽고 hash·dtype·Shape·축·graph·Scale·ReLU 위치·누산 범위를 검사한다.
5. 첫 8장을 Torch INT64 Conv2d와 NumPy INT64 einsum으로 계산해 모든 경계를 비교한다.
6. 같은 패키지로 Test 10,000장을 평가하며 FP32·고정 E2-A도 같은 입력에서 다시 평가한다.
7. 결과·sample별 예측·Golden·소스 hash를 저장한다.

빠른 점검은 `--limit 16 --audit 2`다. 이는 전체 정확도 검증이 아니다.
같은 결과 경로를 갱신하므로 완료한 실행은 ZIP으로 먼저 보관한다.
다른 범위를 시험하려면 새 프로파일·별도 결과로 관리한다. Test 결과를 보고 현재 v1의 Scale을 바꾸지 않는다.

## 6. 직접 검증한 결과

| 항목 | 결과 |
|---|---|
| CPU FP32 | 9,173/10,000 = 91.73% |
| 고정 E2-A signed/minmax | 9,176/10,000 = 91.76% |
| E2-B 실제 정수 | 9,170/10,000 = 91.70% |
| FP32 대비 하락 | 0.03%p |
| E2-A 대비 하락 | 0.06%p |
| 정수↔E2-A 예측 일치 | 99.23% |
| 두 정수 backend 비교 | 8장 × 61경계, 4,416,672원소, 불일치 0 |
| 패키지 저장·재읽기 | 통과 |
| 산술·graph·패키지 등 전체 Python 시험 | 13개 통과 |

Torch/NumPy는 별도 Conv 계산 경로지만 같은 고정 상수를 사용한다. 두 경로의 모든 입력을 전수 비교한 것은 아니다.
작은 signed Conv는 Python 정수 중첩 루프와도 비교했고, 큰 signed/tie RNE는 Fraction의 정확한 유리수 반올림과 비교했다.
파일 변조·잘못된 Add 연결·Conv2 ReLU·GAP 계수·점수 Scale·누산 범위 위반을 거부하는 시험도 통과했다.

허용 정확도 하락 폭은 팀이 정한다. 위 수치로 결과를 보고하며 자동 승인 기준을 새로 만들지 않았다.
실제 RTL과의 code 비교·합성·timing·보드는 이번 E2-B 소프트웨어 검증에 포함하지 않는다.

## 7. 파일과 제출물

| 파일 | 의미 |
|---|---|
| `quant/e2b_export.py` | 학습 모델·고정 범위 → 실제 정수 상수 |
| `quant/e2b_reference.py` | 패키지 검사, NumPy/Torch 정수 실행 |
| `quant/replay_e2b.py` | 데이터 없이 한 장 재실행 |
| `quant/run_e2b.py` | 재export·독립 비교·전체 정확도 평가 |
| `reference/e2b_v1/` | 배포한 상수·Golden·Stem hex·E2-A 출처의 동결본 |
| `artifacts/e2b_v1/` | 실행 시 다시 생성하는 상수 패키지·Stem 벡터 |
| `golden/e2b_sample0/` | 새로 생성한 61개 정수 경계와 manifest |
| `results/e2b_integer.json` | 정확도·범위·독립 비교의 실행 결과 |
| `results/e2b_samples.csv` | sample별 정답·FP32/E2-A/E2-B 예측 |
| `results/e2b_run_manifest.json` | 실행 인자·환경·실행 소스/출처 hash |

제출은 명령·실행자·날짜·패키지 identity·재실행 PASS·첫 Stem 계산 설명·전체/부분 평가 범위·결과·미실행 범위다.
RTL 구현 단계에서는 먼저 이 Stem의 input/weight/bias/N/Shift를 적재하고 acc와 output을 모두 비교한다.
S5의 Golden 준비와 [실제 Stem RTL 비교](stem_e2b_rtl.md)는 완료했다.
같은 sample 0의 Stem 완료 5작업에서 누산·code 각각 81,920개 불일치 0이다.
[첫 실제 Residual Block L1.0](residual_e2b_rtl.md)도 완료 5작업의 Conv acc 163,840개·H/M/Y 245,760개·Add wide 81,920개가 일치했다.
Stem→Block 연속 실행·Transition·전체 CNN RTL·보드는 후속 과제다.

## 확인 질문

1. Bias=11879가 실제 실수 Bias도 11879라는 뜻인가?
2. 왜 Conv2 뒤에 ReLU를 넣으면 안 되는가?
3. 각 Branch를 따로 반올림하면 현재 Add와 같은가?
4. FC 채널별 누산 code를 바로 Argmax하면 왜 위험한가?
5. 소프트웨어 두 구현이 같으면 FPGA timing도 통과한 것인가?

답의 핵심: Bias도 Scale을 가진다. Conv2의 음수 기여를 보존해야 한다. 반올림 순서는 함수의 일부다.
FC 누산의 단위가 채널마다 달라 공통 점수 Scale로 맞춘 뒤 비교한다. 소프트웨어 일치와 FPGA 검증은 별개다.
