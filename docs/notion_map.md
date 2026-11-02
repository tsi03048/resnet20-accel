# Notion 페이지와 실행 파일

| Notion | 저장소 | 현재 상태 |
|---|---|---|
| [기본 트랙](https://app.notion.com/p/40cf0c4baec98145b57af4780d20c752) | docs/basic_track.md, docs/submission_template.md | 학생용 순서·과제·통과 기준 |
| [R0. 수치 기준표](https://app.notion.com/p/40cf0c4baec9816da38eec1d647bef5f) | docs/numbers.md, model/resnet20_plan.py | 크기·MAC·BRAM·DSP·FPS 상한의 단일 근거 |
| [개편 계획](https://app.notion.com/p/40cf0c4baec98122a8afd96a145555de) | — | 결정 기록·충돌 목록(C1~C9)·진행 순서 |
| E1 | model/common.py, model/e1_fp32.py, model/run_reference.py | T4 기존 결과·CPU 91.73% 재검증 |
| E2-A | quant/e2_ptq.py, results/e2_selection.json, results/e2_ptq.json | 개발용 선택 후 한 설정 Test; CPU 91.76% |
| E2-B | quant/e2b_export.py, quant/e2b_reference.py, quant/run_e2b.py, quant/replay_e2b.py | 실제 정수 패키지·61경계 Golden·10,000장 91.70% 검증 완료; Stem·첫 Identity Block RTL 비교 완료 |
| [E14-B 실제 정수 Residual](https://app.notion.com/p/40cf0c4baec981c1a510eb72e9c5ef0f) | docs/residual_e2b_rtl.md, rtl/residual_e2b_v1/, tb/residual_e2b_v1/, results/residual_rtl_actual.json | 실제 sample 0 L1.0 완료 5 Block·모든 중간값/출력 일치; 연속 RTL은 E14-C에서 검증; Transition·보드는 후속 |
| [E14-C Stem→Residual](https://app.notion.com/p/40cf0c4baec9811ba056ff1d3c5dd197) | docs/stem_residual_e2b_rtl.md, rtl/stem_residual_e2b_v1/, tb/stem_residual_e2b_v1/, results/stem_residual_rtl_actual.json | 실제 입력5회·합성0 1회, 전송/전체 중간값/최종값 일치; Transition·보드는 후속 |
| B5·E8 | model/resnet20_plan.py | 9 Block·30 작업·Weight/MAC 구조 계산 |
| 연결05 기본 v1 | rtl/basic_v1/, tb/basic_v1/ | 새 공개 구현; 정상·stall·reset·mismatch 자동 시험 통과 |
| 연결06 | board/zedboard/, board/README.md | VIO 준비 파일; 실제 Vivado·보드 실행 미완료 |
| [E12~E21](historical/e12-e21/README.md) | historical/e12-e21/, docs/historical/e12-e21/ | 원문10개·원본 ZIP9개·E15 Python·소스·기존 로그 이관 완료; 기본 v1과 별도 버전 |
| [00 종합](https://app.notion.com/p/407f0c4baec981f18da0e6c54eb890fb)·[02 핵심 논문](https://app.notion.com/p/408f0c4baec98109964bcee4beace2ec) | — | 논문 학습 지도. 수치는 R0 기준, 이전 논문 페이지의 ResNet-56 계산은 비교 기록 |
| [보관함](https://app.notion.com/p/40cf0c4baec9810c84c9c4150ad5879a) | — | 이전 버전·기획 이력·이전 메인 보충 설명 |

기본 통과 단계는 S0~S6다. D8-Gx·E6-Gx·E11-Gx는 각 문서의 범위가 다른 검증 단계다.
INT8 signed/minmax 구현 목표 채택 기록을 유지하며 실제 정수 계산 검증 완료와 구분한다.
라이선스는 팀원 합의 전 보류(후보 MIT)다.

