# RTL

현재 기본 실습은 **`basic_v1/conv_toy.sv`**다. `tb/basic_v1/run.sh`로 정상·Stall·Reset·고의 mismatch를 시험한다.
새로 작성한 공개 기초 버전이며 아래 기존 ZIP의 복원본이 아니다. 이전 파형 시간표와 섞지 않는다.
실제 통과 기록: https://github.com/tsi03048/resnet20-accel/actions/runs/41391022968
보드 준비 파일은 `board/zedboard/`이며 실제 Vivado·보드 검증은 미완료다.

기존 E12~E21은 [심화 자료 보관함](../docs/historical/e12-e21/README.md)에 원본 ZIP·소스·시험·로그를 이관했다. 원본의 진단용 수치 규약을 유지하며 기본 v1과 구분한다.

| 폴더 | 출처 | 상태 |
| --- | --- | --- |
| `conv_toy/` | 연결 05 (1채널 4×4 → 10·9·8·6) | 이전 예정 · 기본 트랙 S4 |
| `historical/e12-e21/packages/e12_conv_v0/` | E12 (2채널 [2,4,4]) | 원본 ZIP·RTL·Testbench·로그·해시 이관 완료 |
| `historical/e12-e21/packages/` | E13~E16 | Stem·Residual·Transition 원본 이관, E15 Python 포함 |
| `historical/e12-e21/packages/` | E17~E21 | 후처리·상수 검사·Loader·MMIO 원본 이관 완료 |

원본 ZIP의 `source_sha256.json`·로그·도구 식별은 그대로 보존했다. 새 실행은 `python tools/run_historical.py E12 --output build/e12-run`처럼 저장소 최상위에서 별도 폴더에 수행한다.

