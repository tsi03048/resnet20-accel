# 전체 RTL 입력·정수 Golden

실습 설명: [E8-B](../../../../docs/full_e2b_rtl.md).

고정 파일은 `manifest.json`, `sample1_input.hex`, `sample1_source.json`입니다. sample 0은 기존 `../sample0/tensors.npz`, 실제 계수는 `../constants.npz`에서 가져옵니다. 정수 함수와 패키지 식별은 E2-B v1 그대로입니다.

```bash
python -m tools.full_vectors --export
python -m tools.full_vectors
```

이 명령은 저장소 루트에서 실행합니다. `constants/`와 `sample*/`·`layout/`의 hex는 재생성 파일입니다. `constants/`의 weight/bias/N/r와 sample별 input만 DUT loader에 들어갑니다. acc/code/skip/wide/skip_addr와 layout은 테스트 장치가 읽는 비교 기준입니다. 중간 Golden을 회로 bank에 넣지 않습니다.

실제 Test 0/1 각각 입력 포함 61경계, 552,084원소입니다. 완전 실행 1회마다 출력 이벤트 274,506개를 비교합니다. frozen manifest나 graph ROM이 바뀌면 export가 중단됩니다. 잘못된 수치를 새 해시로 숨겨도 verify가 정수 기준과 다시 계산해 거부합니다.

`post/`는 `python -m tools.make_full_post_vectors`가 만드는 Fraction 기반 RNE/포화 단위 시험입니다. 전체 실행의 원본 CSV·로그는 Actions artifact 및 배포 실습 ZIP에서 확인합니다.
