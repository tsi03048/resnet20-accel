# RTL

기존 실습 RTL 은 ChatGPT 라이브러리 ZIP 에 있어 팀원이 받을 수 없었다. 아래 순서로 이곳에 옮긴다.

| 폴더 | 출처 | 상태 |
| --- | --- | --- |
| `conv_toy/` | 연결 05 (1채널 4×4 → 10·9·8·6) | 이전 예정 · 기본 트랙 S4 |
| `conv_fixed/` | E12 (2채널 [2,4,4]) | 이전 예정 · Notion 첨부 `E12_RTL_and_Testbench.md` 에서 복원 가능 |
| `stem/`, `block/`, `transition/` | E13~E16 | 이전 예정 |
| `postproc/`, `loader/`, `mmio/` | E17~E21 | 이전 예정 · 심화 트랙 |

옮길 때 원본 ZIP 의 `source_sha256.json`·로그를 함께 두고, 실행 도구(Verilator 버전)를 README 에 적는다.

