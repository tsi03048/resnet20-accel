# ResNet-20 딥러닝 가속기 프로젝트

**전체 흐름을 먼저 이해하고, 이론을 배운 뒤 계산과 실습으로 확인합니다.**

## 처음 읽을 자료

[전체 흐름부터 읽기](docs/learning/theory_first.md) → A0부터 각 장의 ‘다음 개념’으로 이어갑니다. 기본 이론을 읽은 뒤 계산과 실습을 시작합니다.

이미 읽던 곳으로 돌아갈 때는 [학습 목차](docs/basic_track.md)를 사용합니다.

## 필요한 자료 찾기

| 목적 | 자료 |
| --- | --- |
| 기초 이론 | [개념 자료](docs/fundamentals/README.md) |
| 이론 뒤 확인 실습 | [S0~S6](docs/learning/README.md) |
| 노트북 | [Colab](https://colab.research.google.com/github/tsi03048/resnet20-accel/blob/main/notebooks/E1_E2_resnet20_reference.ipynb) |
| 정수 기준 | [E2-B](docs/e2b_integer_reference.md) |
| 실제 Stem 회로 | [E13-B](docs/stem_e2b_rtl.md) |
| 실제 Stem→Residual 연속 회로 | [E14-C: 실제 전송·자동 시작·정수 비교](docs/stem_residual_e2b_rtl.md) |
| 실제 정수 Transition | [E16-B: stride2·Option A·두 Stage 비교](docs/transition_e2b_rtl.md) |
| 보드 | [ZedBoard](board/README.md) |
| 현재 기준·실행 증거 | [진행 현황](docs/project_status.md) |
| 상세 설계·이전 자료 | [Notion 대응](docs/notion_map.md), [E12~E21 보관](docs/historical/e12-e21/README.md) |

현재 기준은 ResNet-20·CIFAR-10·signed/minmax INT8·ZedBoard입니다. 기본 과제는 작은 Conv 출력 비교이며 전체 모델 분류와 성능 개선은 확장입니다. 라이선스는 팀 합의 전 보류(후보 MIT)이며 참고 구현은 원 라이선스를 따릅니다.
