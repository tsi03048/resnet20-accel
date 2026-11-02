# E12~E21 심화 실습 자료

2026-11-02에 Notion 원문 10개, ChatGPT 라이브러리의 원본 ZIP 9개, E15 Python 첨부를 복구했다.
원본 RTL·Testbench·기준 생성기·로그·벡터·부분 파형을 이제 GitHub에서 받을 수 있다.

| 단계 | 주제 | 원본 패키지 |
|---|---|---|
| [E12](E12.md) | 고정 Conv·RAM·MAC·RNE | [e12_conv_v0.zip](../../../historical/e12-e21/archives/e12_conv_v0.zip) |
| [E13](E13.md) | Stem 크기·Padding1·주소·전체 비교 | [e13_stem.zip](../../../historical/e12-e21/archives/e13_stem.zip) |
| [E14](E14.md) | Identity Residual·Buffer·Add | [e14_residual.zip](../../../historical/e12-e21/archives/e14_residual.zip) |
| [E15](E15.md) | Stride2·Option A·주소 Python 검산 | [Python·기존 결과](../../../historical/e12-e21/packages/e15_reference/) |
| [E16](E16.md) | Transition RTL·중간값·완료 | [e16_transition.zip](../../../historical/e12-e21/archives/e16_transition.zip) |
| [E17](E17.md) | 채널별 Multiplier·Shift·RNE | [e17_requant.zip](../../../historical/e12-e21/archives/e17_requant.zip) |
| [E18](E18.md) | 계수 Table·Snapshot·통합 회귀 | [e18_integrated.zip](../../../historical/e12-e21/archives/e18_integrated.zip) |
| [E19](E19.md) | 상수 Manifest·Hash·범위·Preload | [e19_constants.zip](../../../historical/e12-e21/archives/e19_constants.zip) |
| [E20](E20.md) | Loader·Commit·Prepared·Generation | [e20_loader.zip](../../../historical/e12-e21/archives/e20_loader.zip) |
| [E21](E21.md) | MMIO·Write 응답·Readback | [e21_mmio.zip](../../../historical/e12-e21/archives/e21_mmio.zip) |

소스를 바로 읽으려면 [packages](../../../historical/e12-e21/packages/), 출처와 파일 무결성은 [manifest](../../../historical/e12-e21/manifest.json)를 본다.

## 재실행

저장소 최상위에서 실행한다. 출력 폴더는 매번 새 경로를 지정한다.

```sh
python tools/verify_historical.py
python tools/run_historical.py E15 --output build/e15-python --reference-only
python tools/run_historical.py E19 --output build/e19-python --reference-only
python tools/run_historical.py E12 --output build/e12-rtl
```

Python 검산은 표준 라이브러리만 사용한다. RTL은 Linux의 Bash·Verilator·GCC C++20·make가 필요하다.
E12는 원래 사용한 PyPI `verilator==5.48.0` 도구를 CI에서 고정한다. Ubuntu의 Verilator 5.020에서는 순차 과정의 임시 변수 대입에 BLKSEQ 경고가 발생했다. 나머지 RTL 7단계는 Ubuntu 도구로 재검증한다.
Windows의 Python 실행에서는 원본의 Linux 파일 바이트 규약을 유지하도록 실행기가 LF 쓰기를 적용하며, 원본 소스는 바꾸지 않는다.
E12~E21의 나머지 RTL 단계도 같은 실행기에서 단계 이름을 바꿔 실행한다. E15와 E19는 소프트웨어 검증 단계다.
자동 재검증은 [Historical E12-E21 checks](https://github.com/tsi03048/resnet20-accel/actions/workflows/historical.yml)에서 확인한다.

## 기록을 읽는 기준

기존 원문과 `recorded_results/`의 PASS는 원래 환경에서 선택한 진단용 시험의 기록이다. 새 GitHub 실행의 통과 여부는 Actions 로그를 확인한다.
원본 ZIP 내부의 기존 source hash 831개가 모두 일치하며, 원본 ZIP 전체와 소스 사본도 별도 SHA-256으로 검사한다.
Windows에서 파일 바이트가 변하지 않도록 보관 폴더의 텍스트 자동 변환을 끈다.

현재 구현은 ResNet-20·CIFAR-10·ZedBoard 기준이다. 이 자료의 이전 ResNet-56 기획과 `/4` 진단 수치는 해당 버전의 설명으로 남긴다.
실제 모델 정수 상수와 이 RTL의 연결, FPGA 합성·배치배선·실물 보드·전체 정확도·성능은 별도 검증 범위다.
