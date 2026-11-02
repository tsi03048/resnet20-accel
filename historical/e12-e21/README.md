# E12~E21 원본 자료

[단계별 안내와 원문](../../docs/historical/e12-e21/README.md)

- `archives/`: 라이브러리에서 받은 원본 ZIP 9개. 전체 소스·벡터·로그·부분 파형을 포함하며 바이트를 바꾸지 않았다.
- `packages/`: GitHub에서 읽기 위한 소스 사본. 기존 로그·요약·도구·해시는 `recorded_results/`에 보존한다. 실행에 필요한 전체 벡터는 ZIP에 있다.
- `attachments/`: Notion E12·E13에 별도로 첨부된 원본 소스 문서.
- `packages/e15_reference/`: E15의 Python 검산 코드·기존 결과·원본 첨부. E15는 RTL 단계가 아니다.
- `manifest.json`: 원본 ZIP·내부 파일·소스 사본의 SHA-256과 출처.

저장소 최상위에서 `python tools/verify_historical.py`로 원본 일치 여부를 검사한다.
재실행은 `python tools/run_historical.py E12 --output build/e12-run`처럼 새 폴더에 풀어서 수행한다.
이 폴더의 소스 사본에서 직접 `run.sh`를 실행하면 전체 벡터가 없을 수 있으므로 위 실행기를 사용한다.
원본 결과는 재실행 폴더의 `original_results/`, 새 결과는 `results/`로 분리된다.

기존 report 스크립트에는 과거 배포판·시뮬레이터 버전을 고정한 필드가 있다. 새 실행의 도구는 `migration_environment.json`과 실제 로그를 기준으로 읽는다.
과거 ResNet-56 기획·진단용 정수 규약을 현재 ResNet-20 실제 상수·정확도 또는 FPGA 검증 결과로 확대하지 않는다.
