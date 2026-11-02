# 딥러닝 기초 학습자료

먼저 [전체 흐름](../learning/theory_first.md)을 읽습니다. 모델 기본 → 학습·평가 → CNN → 정수·회로 순서로 개념을 이해한 뒤 [확인 실습](../learning/README.md)으로 이어갑니다.

| 장 | 내용 |
|---|---|
| [A0](A0.md) | Deep Learning은 무엇인가 — 데이터에서 표현과 판단 방법을 배우기 |
| [A1](A1.md) | 이미지를 숫자로 표현하기 — Tensor와 Shape의 의미 |
| [A2](A2.md) | 입력에서 반응을 만들기 — Weight·Bias·Activation Function의 역할 |
| [A3](A3.md) | Layer를 연결해 판단하기 — 데이터 흐름과 분기·합류의 의미 |
| [A4](A4.md) | 예측을 개선하는 방법 — Loss·Gradient·Backpropagation·Optimizer |
| [A5](A5.md) | 새로운 데이터에서도 잘 작동하는가 — 데이터 분리와 Model 평가 |
| [A6](A6.md) | 적은 Bit로 숫자 표현하기 — FP32·INT8과 Quantization |
| [A7](A7.md) | 깊은 Model을 돕는 블록 — Activation·Normalization·Residual Connection |
| [B1](B1.md) | 이미지의 작은 패턴을 계산하기 — Convolution·Filter·Weight Sharing |

자료 기준일은 2026-10-28입니다. 로컬 백업의 수정본 9개와 원본 PNG 9개를 옮겼습니다. Notion 전용 그림·접기·호출문을 GitHub에서 읽을 수 있는 Markdown으로 바꾸고, 포함된 장끼리의 링크를 연결했습니다. 그림과 학습 내용은 유지했습니다.

ResNet-56 등 이전 기획 수치는 현재 ResNet-20 구현의 결과와 구분합니다. 원문·변경 비교·Notion 응답 JSON·중복 ZIP은 로컬 백업에 보존합니다. 이는 Notion 전체의 최신 내보내기가 아닙니다.

변환 전 본문과 그림의 SHA-256은 [출처 기록](provenance.json)에 있습니다.
