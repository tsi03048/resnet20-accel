# ResNet-20 CNN 가속기 학습 프로젝트

**처음이라면 [기본 트랙](docs/basic_track.md)부터 시작한다.**

```sh
python -m exercises.conv_walkthrough
python -m unittest discover -s tests -v
```

Python만으로 Y=[10,9,8,6]과 36 MAC을 먼저 확인한다.
[Colab 실제 이미지 추론](https://colab.research.google.com/github/tsi03048/resnet20-accel/blob/main/notebooks/E1_E2_resnet20_reference.ipynb)

| 항목 | 기준·상태 |
|---|---|
| 모델 | ResNet-20 + CIFAR-10, Option A, 공개 checkpoint·직접 학습 없음 |
| 보드 | ZedBoard XC7Z020-1CLG484; Arty Z7-20은 별도 핀·클록·보드 설정 필요 |
| 기본 과제 | 작은 Conv의 계산·RTL·보드 출력 비교; 실제 모델 Block 연결은 추가 단계 |
| 확장 과제 | Transition·GAP·FC·연속 실행을 포함한 ResNet-20 전체 분류·성능 개선 |
| E1 직접 평가 | CPU 9,173/10,000 = 91.73% |
| E2-A | Train 개발집합에서 먼저 선택한 signed/minmax를 Test 평가: 91.76%, 하락 -0.03%p |
| E2-B | 실제 정수 상수·전체 graph·Golden 구현 및 Test 91.70% 검증 완료; RTL 비교는 별도 |
| 기초 산술·구조표·PTQ·정수 기준 | Python 13개 시험 통과 |
| 기본 RTL v1 | 새 공개 소스·Testbench·자동 시험 제공. 실행 증거는 Actions 확인 |
| 보드 | 합성·배치배선·실행 검증 미완료 |
| 기존 E12~E21 | 이전 ZIP의 저장소 이관 미완료 |

기존 Colab T4 평가(2026-11-02, 370b910)와 **INT8 signed/minmax 채택 결정**을 유지한다.
그 실행의 FP32는 91.73%, signed/minmax는 91.79%였다. 위 CPU 91.76%는 다른 환경의 재검증이다.
E2-A는 fake-quant이며 Bias를 FP32로 유지한다. 정수 RTL 정확도를 증명하지 않는다.
개정 코드의 허용 하락 폭은 미정이면 자동 재결정하지 않는다. 정수 소프트웨어 검증과 실제 모델 RTL·보드 검증은 별개다.

## E2-B 실제 정수 기준

[처음 배우는 사람을 위한 설명](docs/e2b_integer_reference.md) · [Colab 실습](https://colab.research.google.com/github/tsi03048/resnet20-accel/blob/main/notebooks/E2B_integer_reference.ipynb)

데이터 다운로드 없이 실제 상수와 첫 이미지의 정수 입력을 비교한다. NumPy만 필요하다.

```sh
python -m quant.replay_e2b --backend numpy
```

정상 결과: 61개 경계·552,084원소 일치, prediction=3(cat).
전체 재평가: `python -m quant.run_e2b --limit 10000 --audit 8`.
실제 정수 9,170/10,000=91.70%, FP32 대비 하락 0.03%p. Torch/NumPy 정수 8장·4,416,672원소 불일치 0.
고정 Bias·Multiplier/Shift·Add·GAP·공통 FC 점수 규칙과 파일 hash를 검사한다.
상수·Golden·Stem hex는 `reference/e2b_v1/`, 결과는 `results/e2b_integer.json`이다.

로컬: `python -m pip install -r requirements.txt` 후 `python -m model.run_reference --device cpu`.
Colab은 T4를 선택하고 노트북을 순서대로 실행한다. CPU도 가능하다.
결과는 `results/`, FP32 텐서는 `golden/e1_sample0/`에 생성된다.
RTL은 Ubuntu에 Icarus Verilog를 설치한 뒤 `bash tb/basic_v1/run.sh`.
새 기본 RTL은 이전 개인 ZIP의 복원본이 아니며 기존 파형 시간표를 재사용하지 않는다.

[제출 양식](docs/submission_template.md) · [노션 대응표](docs/notion_map.md)

실행 소스 hash·환경·입력/상수·기대/실제 출력·실패·미실행 범위를 기록한다.
체크포인트 저장값 91.78%와 이번 직접 평가 91.73%를 구분한다.
Train 1,000장 보정 + 겹치지 않는 Train 1,000장 설정 선택 후 하나만 Test에 평가한다.
이 개발집합은 공개 체크포인트 학습 이력과 독립적이지 않다. Test를 보고 재선택하면 탐색 이력을 남긴다.

라이선스는 **보류**다. 팀원 합의로 결정하며 후보는 MIT다. 참고 구현의 라이선스는 원 저장소를 따른다.

