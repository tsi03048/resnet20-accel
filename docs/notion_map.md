# Notion 페이지와 실행 파일

| Notion | 저장소 | 현재 상태 |
|---|---|---|
| 기본 트랙 | docs/basic_track.md, docs/submission_template.md | 학생용 순서·과제·통과 기준 |
| R0. 수치 기준표 | docs/numbers.md, model/resnet20_plan.py | 크기·MAC·BRAM·DSP·FPS 상한의 단일 근거 |
| 개편 계획 | — | 결정 기록·충돌 목록(C1~C9)·진행 순서 |
| E1 | model/common.py, model/e1_fp32.py, model/run_reference.py | T4 기존 결과·CPU 91.73% 재검증 |
| E2-A | quant/e2_ptq.py, results/e2_selection.json, results/e2_ptq.json | 개발용 선택 후 한 설정 Test; CPU 91.76% |
| E2-B | quant/e2b_export.py, quant/e2b_reference.py, quant/run_e2b.py, quant/replay_e2b.py | 실제 정수 패키지·61경계 Golden·10,000장 91.70% 검증 완료; Stem·첫 Identity Block RTL 비교 완료 |
| E14-B 실제 정수 Residual | docs/residual_e2b_rtl.md, rtl/residual_e2b_v1/, tb/residual_e2b_v1/, results/residual_rtl_actual.json | 실제 sample 0 L1.0 완료 5 Block·모든 중간값/출력 일치; 연속 RTL은 E14-C에서 검증; Transition은 E16-B에서 단위 검증; 전체 모델은 E8-B, 보드는 후속 |
| E14-C Stem→Residual | docs/stem_residual_e2b_rtl.md, rtl/stem_residual_e2b_v1/, tb/stem_residual_e2b_v1/, results/stem_residual_rtl_actual.json | 실제 입력5회·합성0 1회, 전송/전체 중간값/최종값 일치; Transition·보드는 후속 |
| E16-B 실제 Transition | docs/transition_e2b_rtl.md, rtl/transition_e2b_v1/, tb/transition_e2b_v1/, results/transition_rtl_actual.json | L2.0·L3.0 각5회, stride2·Option A·전체 중간값/출력 일치; 전체 모델은 E8-B, 보드는 후속 |
| B5·E8 | model/resnet20_plan.py | 9 Block·30 작업·Weight/MAC 구조 계산 |
| E8-I Hold 여유 확보 | docs/hold_margin.md, board/zedboard/ps_dma_hold/, tools/check_hold_delivery.py, results/ps_dma_hold_*.json | 기존 조건 Hold+0.119ns·추가0.100ns 목표+0.019ns, Setup+0.972ns; 동일 RTL61경계·Stall·Reset 재검증, 실물 NOT_RUN |
| E8-H 패킷 수신부 Setup 개선 | docs/timing_margin.md, rtl/ps_dma_v3/, tb/ps_dma_timing/, board/zedboard/ps_dma_timing/, results/ps_dma_timing_*.json | 100 MHz WNS+0.055→+0.927ns, WHS+0.007ns. 61경계·Stall·11곳 Reset·추가 byte Reset 재검증, 계산 클록·R202 ABI 동일; 실물 NOT_RUN |
| E8-G MAC 파이프라인 | docs/pipelined_mac.md, rtl/full_e2b_fpga_v3/, tb/ps_dma_v3/, board/zedboard/ps_dma_pipe/, results/ps_dma_pipe_*.json | 실제 계산 클록75.92% 감소, 61경계·Stall·11곳 Reset·108항 부분합 시험, 전체 시스템100 MHz WNS+0.055ns·WHS+0.018ns; 실물 NOT_RUN |
| E8-F INT8 묶음 DMA | docs/packed_dma.md, rtl/ps_dma_v2/, tb/ps_dma_v2/, board/zedboard/ps_dma_packed/, results/ps_dma_packed_*.json | R202: MM2S 1,094,068→279,844bytes, 74.42% 절감. 61경계·Stall·Reset 및 추가 lane Reset·숫자 오류 drain 통과. 전체 시스템 100 MHz 배선 WNS +0.571ns·WHS +0.033ns; 실물 NOT_RUN |
| E8-E PS·DDR·AXI DMA | docs/ps_ddr_dma.md, rtl/ps_dma_v1/, tb/ps_dma_v1/, board/zedboard/ps_dma/, tools/ps_dma_*.py, results/ps_dma_*.json | 실제 PS7·DDR·GP0/HP0·DMA 전체 시스템 bitstream/XSA 생성·100 MHz 배선 통과, RTL 61경계·Stall·8곳 Reset 및 실제 DMA IP·ARM 에뮬레이션 통과; 실물 보드 NOT_RUN |
| E8-D 전체 BRAM·100 MHz 개선 | docs/full_fpga_v2.md, rtl/full_e2b_fpga_v2/, tb/full_e2b_fpga_v2/, results/vivado_v2_actual.json, results/full_fpga_v2_rtl_actual.json | 전체 Weight·계수 BRAM, 주소 단계화; 실제 코어 배선 후 LUT 1,957·BRAM 84.5·WNS +0.071 ns·WHS +0.052 ns; 최종 top 0→1→0·61경계·Stall·7곳 Reset 재검증 통과 |
| E8-C 전체 코어 ZedBoard 합성 | docs/full_vivado_zedboard.md, board/zedboard/build_full.tcl, rtl/full_e2b_fpga_v1/, results/vivado_full_actual.json | Vivado 2025.1 합성 완료; LUT 자원 초과·100 MHz 시간 조건 위반, 배치 중단; BRAM 포트 버전의 정수 회귀 시험은 통과 |
| E8-B 실제 전체 모델 RTL | docs/full_e2b_rtl.md, rtl/full_e2b_v1/, tb/full_e2b_v1/, tools/full_vectors.py, results/full_rtl_actual.json | 실제 0→1→0·61경계·점수10개·예측, Stall·Reset 후 재실행 일치; 완료5회·실제이미지2종; 보드는 후속 |
| 연결05 기본 v1 | rtl/basic_v1/, tb/basic_v1/ | 새 공개 구현; 정상·stall·reset·mismatch 자동 시험 통과 |
| 연결06 | board/zedboard/, board/README.md | VIO 준비 파일; 실제 Vivado·보드 실행 미완료 |
| [E12~E21](historical/e12-e21/README.md) | historical/e12-e21/, docs/historical/e12-e21/ | 원문10개·원본 ZIP9개·E15 Python·소스·기존 로그 이관 완료; 기본 v1과 별도 버전 |
| 00 종합·02 핵심 논문 | — | 논문 학습 지도. 수치는 R0 기준, 이전 논문 페이지의 ResNet-56 계산은 비교 기록 |
| 보관함 | — | 이전 버전·기획 이력·이전 메인 보충 설명 |

기본 통과 단계는 S0~S6다. D8-Gx·E6-Gx·E11-Gx는 각 문서의 범위가 다른 검증 단계다.
INT8 signed/minmax 구현 목표 채택 기록을 유지하며 실제 정수 계산 검증 완료와 구분한다.
라이선스는 팀원 합의 전 보류(후보 MIT)다.

