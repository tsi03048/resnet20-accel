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
| 실제 Identity L1.0 RTL | [841f6cf9 통과](https://github.com/tsi03048/resnet20-accel/actions/runs/41399400691): 같은 sample 0 완료 5 Block, Conv acc 163,840개·H/M/Y 245,760개·Add wide 81,920개 불일치 0; [실습](residual_e2b_rtl.md) |
| 실제 Stem→L1.0 연속 RTL | [b9bf7d50 통과](https://github.com/tsi03048/resnet20-accel/actions/runs/41402525320): 실제 sample 0 5회·합성0 1회, 연결 98,304개·acc 294,912개·code 393,216개·Add wide 98,304개 일치; [실습](stem_residual_e2b_rtl.md) |
| 실제 Transition L2.0·L3.0 RTL | [43cd6a45 통과](https://github.com/tsi03048/resnet20-accel/actions/runs/41404611983): 각5회, acc 122,880개·H/M/Y 184,320개·Skip/Add wide 각각61,440개 일치; [실습](transition_e2b_rtl.md) |
| 첫 전체 코어 ZedBoard OOC 합성(이전 v1) | Vivado 2025.1 실제 합성 완료. LUT 88,171/53,200, LUT RAM 51,372/17,400 초과; 100 MHz 합성 WNS −121.450 ns. 자원 DRC로 배치 중단; [실패 기록](full_vivado_zedboard.md) |
| 전체 메모리 BRAM·100 MHz 개선(v2) | Vivado 2025.1 실제 코어 배치·배선 통과. LUT 1,957/53,200, FF 1,759/106,400, BRAM 84.5/140, DSP 0; WNS +0.071 ns·WHS +0.052 ns, TNS/THS 0. [E8-D](full_fpga_v2.md); [최종 top의 0→1→0·61경계·Stall·7곳 Reset 통과](https://github.com/tsi03048/resnet20-accel/actions/runs/41430880747) |
| PS·DDR·AXI DMA 전체 시스템 | [E8-E](ps_ddr_dma.md): 실제 시스템 bitstream/XSA 생성·100 MHz 배선 통과. LUT 4,296·FF 5,625·BRAM 87.5·DSP 0, WNS +0.255 ns·WHS +0.017 ns. 최종 적재·점수 회수 RTL 61경계·Stall·8곳 Reset 및 실제 DMA IP·ARM 소프트웨어 모델 시험 통과. IP 경고는 보존 |
| INT8 묶음 DMA R202 | [E8-F](packed_dma.md): MM2S 1,094,068→279,844bytes(74.42% 절감). 전체 RTL 완료5회·61경계·점수·예측 일치, Stall·8곳 Reset 및 추가 lane Reset·숫자 오류 drain 통과. LUT 4,432·FF 5,706·BRAM 87.5·DSP 0, 100 MHz WNS +0.571ns·WHS +0.033ns. 정상 계산 클록은 이전과 동일 |
| MAC 파이프라인 v3 | [E8-G](pipelined_mac.md): 실제 정상3회 각각266,085,373→64,063,653클록(75.92% 감소), 61경계·점수·예측 및 Stall·11곳 Reset 회복 통과. 108항 독립 부분합 시험 통과. 전체 시스템 LUT4,456·FF5,653·BRAM87.5·DSP0, 100 MHz WNS+0.055ns·WHS+0.018ns; 실물 NOT_RUN |
| 패킷 수신부 Setup 개선 | [E8-H](timing_margin.md): 헤더 수신 시 끝 주소 저장, 100 MHz WNS+0.055→+0.927ns, WHS+0.007ns. LUT4,425·FF5,655·BRAM87.5·DSP0. 0→1→0·61경계·Stall·11곳 Reset 재검증 및 추가 lane Reset 통과. 정상64,063,653클록·R202 전송 길이 동일. Hold 여유는 작음 |
| Hold 여유 확보 | [E8-I](hold_margin.md): 기존 조건 WHS+0.007→+0.119ns, 추가0.100ns 목표에서도 WHS+0.019ns, Setup WNS+0.972ns. LUT4,543·FF5,655·BRAM87.5·DSP0. 동일 RTL의61경계·Stall·11곳 Reset·추가 byte Reset 재실행 및 Python60개 검사 통과. 정상 계산64,063,653클록·R202 ABI 동일 |
| ZedBoard 실물 실행 | 사용자가 보드 없이 후속 작업을 요청했고 JTAG 감지0개를 확인함. 실제 PS 실행·DDR 초기화·DMA·점수 회수는 NOT_RUN; 실행 스크립트와 같은 빌드의 bit/ELF는 실습 ZIP에 포함 |
| 실제 전체 ResNet-20 RTL | [60f37028 통과](https://github.com/tsi03048/resnet20-accel/actions/runs/41409298942): 실제 0→1→0, 완료 5회(정상3·Stall1·Reset 회복1), 61경계/회·점수·예측 일치, 경계 원소 2,760,420개 불일치 0; [실습](full_e2b_rtl.md) |

기존 T4 fake-quant 91.79%는 위 CPU 91.76%와 다른 실행입니다. checkpoint 저장값 91.78%도 직접 평가가 아닙니다. 수치 구조는 [R0 대응 문서](numbers.md), 실제 증거는 [Actions](https://github.com/tsi03048/resnet20-accel/actions)와 results/를 확인합니다.

실제 Stem·Residual·Transition 단위와 전체 모델 RTL 시뮬레이션이 통과했습니다. Weight/계수 BRAM 전환·주소 단계화·순차 곱셈/RNE를 적용한 v2도 최종 top으로 0→1→0·Stall·7곳 Reset 취소 후 재실행을 통과했습니다. 완료5회·매회61경계·점수·예측 일치이며 경계 원소 2,760,420개 불일치0입니다. 전체 모델은 실제 Test 0/1 두 종류이며 10,000장 RTL 정확도 평가는 미실행입니다. v2 코어 OOC는 자원과 100 MHz 배선 후 Setup/Hold를 통과했지만 여유가 작고 입출력 예산·클록 진입 위치가 고정된 결과입니다. 후속 E8-E에서 CPU 제어·AXI DMA와 전체 시스템 배치배선·bitstream 생성까지 구현·검증했습니다. 실물 보드가 연결되지 않아 실제 PS·DDR·DMA 실행과 보드 실측은 남아 있습니다. 이전 E12~E21 원문·ZIP·소스·기존 로그는 historical/e12-e21/에 이관되어 있습니다. 목표 FPS·정확도 허용치·라이선스는 팀 결정 기록을 따르며 라이선스는 보류(후보 MIT)입니다.
