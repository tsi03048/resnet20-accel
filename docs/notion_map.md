# Notion 페이지 ↔ 저장소 대응

| Notion | 저장소 | 상태 |
| --- | --- | --- |
| E1. 같은 모델을 같은 숫자로 재현하기 | `model/common.py`, `model/e1_fp32.py`, 노트북 1~2 | 첫 실행 대기 |
| E2. 같은 계산을 정수로 옮기기 | `quant/e2_ptq.py`, 노트북 E2 | 첫 실행 대기 (INT8 채택 근거 단계) |
| 연결 05. 첫 Conv RTL과 파형 읽기 | `rtl/conv_toy/`, `tb/conv_toy/` | 이전 예정 |
| E12~E21 | `rtl/`, `tb/` 단계별 폴더 | 이전 예정 |
| 연결 06. Simulation에서 FPGA까지 | `board/zedboard/` | 예정 |

## 결정 기록 (요약)

- 2026-11-02: 기준 모델 ResNet-20, 공개 checkpoint 사용(학습 없음), Colab 실행, INT8 은 하락 폭 측정 후 결정, 기준 보드 ZedBoard, 저장소 공개.
