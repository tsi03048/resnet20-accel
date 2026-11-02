# Golden 파일

`python -m model.run_reference` 또는 Colab 실행 시 `e1_sample0/*.npy`와 manifest가 생성된다.
공개 저장소에는 manifest만 기록하고, 실제 FP32 배열은 실행 후 결과 ZIP으로 보관한다.
manifest의 파일명·Shape·Dtype·파일 hash로 로컬 배열을 검사한다.
이 FP32 자료는 E2-B의 정수 RTL Golden이 아니다.

E2-B의 실제 정수 Golden은 `reference/e2b_v1/sample0/`에 동결해서 배포한다.
`python -m quant.replay_e2b --backend numpy`로 61개 경계를 비교한다.
새로 생성한 값은 `golden/e2b_sample0/`에 저장한다. 각 경계의 dtype·Shape·hash는 manifest에 있다.
실제 모델 RTL과 이 Golden의 비교는 아직 수행하지 않았다.
