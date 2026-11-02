# Notion 페이지와 실행 파일

| Notion | 저장소 | 현재 상태 |
|---|---|---|
| [기본 트랙](https://app.notion.com/p/40cf0c4baec98145b57af4780d20c752) | docs/basic_track.md, docs/submission_template.md | 학생용 순서·과제·통과 기준 |
| E1 | model/common.py, model/e1_fp32.py, model/run_reference.py | T4 기존 결과·CPU 91.73% 재검증 |
| E2-A | quant/e2_ptq.py, results/e2_selection.json, results/e2_ptq.json | 개발용 선택 후 한 설정 Test; CPU 91.76% |
| E2-B | quant/integer_math.py | 산술 helper만 제공; 실제 모델 정수 exporter·Golden 미완료 |
| B5·E8 | model/resnet20_plan.py | 9 Block·30 작업·Weight/MAC 구조 계산 |
| 연결05 기본 v1 | rtl/basic_v1/, tb/basic_v1/ | 새 공개 구현; 정상·stall·reset·mismatch 자동 시험 통과 |
| 연결06 | board/zedboard/, board/README.md | VIO 준비 파일; 실제 Vivado·보드 실행 미완료 |
| E12~E21 | 기존 Notion의 단계별 진단용 시험 기록 | 기존 ZIP 전체 이관 미완료; 기본 v1과 별도 버전 |

기본 통과 단계는 S0~S6다. D8-Gx·E6-Gx·E11-Gx는 각 문서의 범위가 다른 검증 단계다.
INT8 signed/minmax 구현 목표 채택 기록을 유지하며 실제 정수 계산 검증 완료와 구분한다.
라이선스는 팀원 합의 전 보류(후보 MIT)다.

