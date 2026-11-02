# 처음 시작하는 기본 트랙

목표는 **CNN이 계산하는 값을 이해하고, 같은 작은 Conv를 회로로 실행해 비교하는 것**이다.
기본 과제의 최종 제출은 ZedBoard에서 실행한 작은 Conv 또는 Residual Block의 결과와 검증 기록이다.
ResNet-20 전체 이미지 분류는 확장 트랙이다. 기본 과제의 Block 실행을 전체 CNN 구현으로 표현하지 않는다.
S5는 실제 모델 Block으로 확장할 때 필요한 확인 항목이며, 현재 E2-A 결과로 대체하지 않는다.

| 단계 | 먼저 읽기 | 직접 할 일 | 제출물·통과 조건 |
|---|---|---|---|
| S0 첫 계산 | A0의 학습/추론, A1의 Shape, B1, 연결02 | `python -m exercises.conv_walkthrough` | Y=[10,9,8,6], 36 MAC, CSV 첫 출력 주소 설명 |
| S1 실제 예측 | A2·A3의 흐름, B3의 Logits, E1 | Colab E1·E2 노트북에서 E1 실행 | 1장 label/prediction, [1,10] logits, 전체 10,000장 정확도·환경·파일 hash |
| S2 학습과 평가 | A4·A5, B4, 연결01·04 | 작은 Weight 갱신과 Residual 손계산 | 학습/추론·Loss/정확도·두 경로 보존을 자기 말로 설명 |
| S3 정수 표현 | A6·D1, E2-A | 보정/개발 Index 확인, fake-quant 비교 | 두 집합 겹침 0, 개발용 선택 기록, 선택한 설정의 Test 결과; E2-B 정수 검증 완료 아님 |
| S4 첫 RTL | 연결03·05, D2·D5 필요한 절 | `bash tb/basic_v1/run.sh` | 정상·stall·reset 통과, 고의 mismatch 거부, 로그·VCD |
| S5 선택: 모델 Block 연결 | E2-B, E3·E13·E14 | 실제 계수·bias·정수 Golden으로 Stem/Block 비교 | [실제 Stem 실습](stem_e2b_rtl.md): sample 0 완료 5작업·누산/code 각각 81,920개 불일치 0; Residual·전체 CNN·보드는 후속 |
| S6 보드 | 연결06, board/README.md | X/W 준비→시작→Y 회수→기준 비교 | 보드 로그·출력 일치·part/XDC·timing·자원 보고서; 현재 보드 실행 미완료 |

최소 기본 경로는 S0~S4 → S6 작은 Conv 보드 실행이다. S5는 실제 모델 Block 연결을 선택할 때 진행한다.
S5·S6은 준비 상태와 실행 결과를 구분한다. 학습 일정·정확도 허용치는 팀이 정한다.

## 10분 첫 실습: Python만 있으면 된다

저장소 폴더 안에서 다음을 실행한다. 이 단계에는 PyTorch·GPU·CIFAR 다운로드가 필요 없다.

```sh
python -m exercises.conv_walkthrough
python -m unittest discover -s tests -v
```

정상 출력은 `Y = [10, 9, 8, 6] ; 36 MAC; PASS`다. `results/basic/conv_trace.csv`의 첫 9행에서
입력 주소 0,1,2,4,5,6,8,9,10과 Psum 5,5,4,8,8,7,10,10,10을 확인한다.

연습: X[0][0]을 5에서 6으로 바꾸면 어떤 출력이 달라질까? 먼저 손으로 예측하고 확인한다.
그다음 W의 -1을 +1로 바꿔 기대값 비교가 실패하는지 본다. 원본을 복원한 뒤 제출한다.

## 실제 이미지 추론: Colab 권장

[E1·E2-A 노트북 열기](https://colab.research.google.com/github/tsi03048/resnet20-accel/blob/main/notebooks/E1_E2_resnet20_reference.ipynb)

1. 런타임 유형에서 T4 GPU를 선택한다. CPU도 실행 가능하다.
2. 위에서부터 한 셀씩 실행한다. `device` 출력과 첫 이미지의 정답·예측을 확인한다.
3. 전체 평가를 마친 후 결과 ZIP을 다운로드한다. 세션 종료 전에 저장한다.
4. 결과 JSON의 Test 10,000장·checkpoint hash·데이터 hash·환경·실행 소스 hash를 확인한다.

로컬은 Python 환경에 `python -m pip install -r requirements.txt` 후
`python -m model.run_reference --device cpu`로 실행한다.
Windows에서 프로젝트 경로에 한글이 있어도 Python 실습은 가능하다. RTL 도구 설치는 별도다.

## E2-A와 E2-B 구분

E2-A는 Weight/Activation의 반올림·clipping 영향을 FP32 연산으로 탐색한다. Bias는 FP32다.
Train 1,000장으로 보정하고, 겹치지 않는 Train 1,000장으로 설정을 선택한 뒤 선택한 하나만 Test에 평가한다.
공개 체크포인트는 Train 전체를 학습했으므로 이 개발용 집합은 독립적인 일반화 검증 집합이 아니다.
기존 Colab 평가에 따른 INT8 signed/minmax 구현 목표 채택을 유지한다. 개정 코드의 허용 하락 폭은 기본 `None`이며 자동 재결정하지 않는다.
Test를 본 뒤 재선택하면 탐색 이력을 남긴다. 구현 목표 채택이 E2-B 검증 완료를 뜻하지 않는다.

E2-B는 INT32 Bias·Multiplier/Shift·실제 Add/GAP/FC 규칙까지 고정한 정수 기준이다.
`quant/integer_math.py`는 산술 helper이며, 실제 exporter·정수 실행은 `quant/e2b_export.py`·`quant/e2b_reference.py`다.
[E2-B 따라하기](e2b_integer_reference.md)에서 NumPy만으로 실제 첫 이미지의 61개 정수 경계를 재현한다.
Test 정수 정확도는 91.70%, FP32 대비 하락은 0.03%p다. Golden 준비와 [실제 Stem RTL 비교](stem_e2b_rtl.md)는 완료했다. Residual·전체 CNN RTL·보드는 후속 과제다.

## 기본 RTL v1

`rtl/basic_v1/conv_toy.sv`는 위 X/W를 ROM으로 고정한 새 기초 구현이다. 이전 ZIP의 복원본이 아니다.
Signed 8-bit 입력·weight, 16-bit 곱, 32-bit 누산·출력을 사용한다. 각 항을 등록한 뒤 MAC하며,
`mac_ready=0`에서 계산을 보류하고 `y_valid && y_ready`에서만 출력을 수락한다.
Y 메모리·CPU·DMA·실제 학습 weight는 포함하지 않는다. 이전 노션 파형의 cycle/ns 수치와 직접 비교하지 않는다.

Ubuntu에서 `sudo apt-get install iverilog` 후 `bash tb/basic_v1/run.sh`를 실행한다.
GitHub Actions의 Basic track checks도 같은 시험을 실행하고 로그·파형을 artifact로 보관한다.
파형은 `gtkwave results/basic_rtl/mode1.vcd`로 열 수 있다. GTKWave는 별도 설치한다.

| Mode | 확인할 내용 |
|---|---|
| 0 | 출력 4개, MAC 36회, 완료 |
| 1 | MAC/출력 대기를 넣어도 같은 값·순서, 출력 hold |
| 2 | 계산 중 reset 취소 후 이전 출력 없이 새 작업 완료 |
| 3 | 기대값 10을 11로 바꾸면 실패; 스크립트가 해당 mismatch 검출을 확인 |

## 전체 모델 확장에 필요한 것

ResNet-20은 Stem + 9 Block + GAP + FC다. Conv 19 + Add 9 + GAP 1 + FC 1 = 30 논리 작업이다.
Stage2·3의 첫 Block은 stride2·Option A가 필요하다. Stem/Identity만으로 전체 모델을 실행할 수 없다.
확장에서는 Transition·전체 descriptor·상수 선택·buffer 회전·GAP·FC·10,000장 정확도까지 추가 검증한다.

## 막히면 먼저 볼 것

| 증상 | 먼저 확인 |
|---|---|
| `No module named ...` | 저장소 최상위에서 실행했는지, 필요한 환경인지 |
| CPU로 표시됨 | Colab T4 선택·연결 후 런타임 재시작 |
| 데이터 다운로드 지연 | hf 경로 기본, 실패하면 toronto; 재시도 시 이미 받은 데이터 재사용 |
| BN folding mismatch | 후속 PTQ 중단, 버전·eval·체크포인트·연산 순서 확인 |
| RTL 명령 없음 | Icarus 설치 또는 GitHub Actions 로그 이용 |
| 최종 class만 같음 | Logits·중간값 일치 시험을 별도로 수행 |

## 제출 기록

실행자·날짜·S단계·소스 revision/hash·도구 버전·입력/상수 식별·기대/실제 출력·상태·실패 원인·미실행 범위를 남긴다.
상태는 `PASS / FAIL / NOT_RUN / BLOCKED`를 사용한다. 문서 작성 완료와 실행 통과는 별도로 기록한다.
