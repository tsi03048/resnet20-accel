# resnet20-accel — ResNet-20 CIFAR-10 CNN 가속기 (ZedBoard)

처음 딥러닝을 배우는 팀원이 **FP32 재현 → INT8 기준 → Conv RTL → Residual Block → ZedBoard 실행**까지
같은 숫자로 따라가는 학습·설계 프로젝트의 실습 저장소다. 설명 문서는 Notion "딥러닝 프로젝트"에 있고,
이 저장소에는 실행 코드·기준 데이터·RTL·로그를 둔다.

## 기준 (2026-11-02 결정)

| 항목 | 기준 |
| --- | --- |
| 모델 | ResNet-20 + CIFAR-10 (Option A shortcut). ResNet-56 은 확장 기준 |
| Checkpoint | 공개 [`akamaster/pytorch_resnet_cifar10`](https://github.com/akamaster/pytorch_resnet_cifar10) `resnet20-12fca82f.th` @ `d5489e8`, 직접 학습하지 않음 |
| 실행 환경 | Google Colab |
| 정밀도 | **INT8 채택 (2026-11-02)** · W8A8 signed·minmax: Weight 출력 채널별 대칭 [-127,127], Activation Tensor별 signed [-128,127]·zero-point 0, RNE |
| 보드 | ZedBoard (XC7Z020). Arty Z7-20 은 같은 PL 이라 호환 |

## 바로 실행

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/tsi03048/resnet20-accel/blob/main/notebooks/E1_E2_resnet20_reference.ipynb)

`notebooks/E1_E2_resnet20_reference.ipynb` — E1(FP32 직접 평가·Golden Tensor) + E2(INT8 하락 측정).

## 폴더

```
model/      E1 — 고정 모델 로딩·평가·Golden Tensor 저장
quant/      E2 — BN Folding·PTQ fake-quant (INT8 채택 근거)
notebooks/  Colab 노트북
results/    실행 결과 JSON (실행할 때 생성)
golden/     Layer 경계별 기준 Tensor (실행할 때 생성)
rtl/        단계별 RTL (연결 05 conv_toy, E12 conv_fixed …)
tb/         Testbench·run.sh·로그
board/      ZedBoard XDC·Vivado Tcl·보드 로그
docs/       Notion 페이지 대응표·결정 기록
```

## 진행 상태

| 단계 | 상태 |
| --- | --- |
| E1 FP32 재현 | **완료** (2026-11-02, Colab T4) · Test Top-1 **91.73%** (9173/10000) |
| E2 INT8 하락 측정 | **완료** · W8A8 6개 설정 모두 하락 ±0.07%p 이내 → INT8 채택 |
| E2b 정수 Reference | 다음 단계 · INT32 bias·Multiplier/Shift·RNE 로 bit-exact 기준 고정 |
| 기존 RTL (연결 05, E12~E21) | 이전 예정 (`rtl/README.md`) |

## 기록 규칙

- 결과를 올릴 때는 `results/code_commit.txt`(실행한 commit)를 함께 올린다.
- "실행해서 확인한 것"과 "예제·계획"을 구분한다. 실행하지 않은 결과를 PASS 로 적지 않는다.
- 모델·전처리·양자화 규칙을 바꾸면 새 버전으로 기록하고 이전 결과와 섞지 않는다.

참고 구현의 라이선스는 해당 저장소의 LICENSE 를 따른다. 이 저장소 자체의 라이선스는 아직 정하지 않았다.
