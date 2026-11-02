# 현재 기준과 진행 상태

학습은 [단계별 경로](learning/README.md)에서 시작합니다.

기준은 ResNet-20 + CIFAR-10, Option A, 공개 checkpoint·직접 학습 없음, signed/minmax INT8, ZedBoard XC7Z020-1CLG484입니다. 실제 정수 규칙은 [E2-B v1](e2b_integer_reference.md)을 따릅니다.

| 실행 범위 | 기록 |
| --- | --- |
| CPU FP32 | Test 9,173/10,000 = 91.73% |
| CPU E2-A fake-quant | Test 91.76%; 정수 RTL 증거 아님 |
| CPU E2-B 실제 정수 | Test 9,170/10,000 = 91.70%; FP32 대비 하락 0.03%p |
| 두 정수 구현 비교 | 8장·61경계·4,416,672원소 불일치 0 |
| 기본 RTL v1 | 정상·Stall·Reset·고의 mismatch와 board wrapper 자동 시험 통과 |
| 실제 Stem RTL | [5fef496f 실제 통과](https://github.com/tsi03048/resnet20-accel/actions/runs/41396748645): 같은 sample 0로 완료 5작업, 누산·code 각각 81,920개 불일치 0; [실습 설명](stem_e2b_rtl.md) |
| ZedBoard | 합성·배치배선·실제 보드 실행 미완료 |

기존 T4 fake-quant 91.79%는 위 CPU 91.76%와 다른 실행입니다. checkpoint 저장값 91.78%도 직접 평가가 아닙니다. 수치 구조는 [R0 대응 문서](numbers.md), 실제 증거는 [Actions](https://github.com/tsi03048/resnet20-accel/actions)와 results/를 확인합니다.

실제 Stem 하나, Residual, 전체 모델 RTL, FPGA는 각각 별도 검증 범위입니다. 이전 E12~E21 원문·ZIP·소스·기존 로그는 historical/e12-e21/에 이관되어 있습니다. 목표 FPS·정확도 허용치·라이선스는 팀 결정 기록을 따르며 라이선스는 보류(후보 MIT)입니다.
