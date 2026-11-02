# Golden 파일

`python -m model.run_reference` 또는 Colab 실행 시 `e1_sample0/*.npy`와 manifest가 생성된다.
공개 저장소에는 manifest만 기록하고, 실제 FP32 배열은 실행 후 결과 ZIP으로 보관한다.
manifest의 파일명·Shape·Dtype·파일 hash로 로컬 배열을 검사한다.
이 FP32 자료는 E2-B의 정수 RTL Golden이 아니다.
