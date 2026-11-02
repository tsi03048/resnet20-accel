"""Maintain the small teaching notebooks from plain cell text."""
import json
from pathlib import Path


def cell(kind, text):
    data = dict(cell_type=kind, metadata={}, source=text.splitlines(keepends=True))
    if kind == "code":
        data.update(execution_count=None, outputs=[])
    return data


setup = '''# 0. 저장소 준비. 다시 실행해도 폴더 안에 중첩 복제하지 않는다.
import os, sys, subprocess
from pathlib import Path
repo = Path('/content/resnet20-accel') if Path('/content').is_dir() else (Path.cwd() if (Path.cwd() / 'model/common.py').exists() else Path.cwd() / 'resnet20-accel')
if not (repo / 'model/common.py').exists():
    subprocess.run(['git', 'clone', 'https://github.com/tsi03048/resnet20-accel.git', str(repo)], check=True)
os.chdir(repo)
sys.path.insert(0, str(repo))
print('실행 폴더:', repo)
subprocess.run(['git', 'rev-parse', 'HEAD'], check=True)
'''
cells = [cell("markdown", """# ResNet-20 기본 실습 — 첫 계산 → 실제 예측 → INT8 후보 평가

학습된 모델을 가져와 추론한다. 새 모델을 학습하지 않는다.
런타임 → 런타임 유형 변경 → **T4 GPU** 선택 후 위에서부터 한 셀씩 실행한다. CPU도 가능하다.
[기본 트랙](https://github.com/tsi03048/resnet20-accel/blob/main/docs/basic_track.md)
"""), cell("code", setup), cell("code", """# 1. 먼저 작은 계산: GPU·PyTorch 없이 36 MAC 확인
subprocess.run([sys.executable, '-m', 'exercises.conv_walkthrough'], check=True)
"""), cell("markdown", """## 손으로 먼저 확인

왜 출력이 네 개인가? 첫 출력의 X 주소는 왜 0,1,2,4,5,6,8,9,10인가?
`results/basic/conv_trace.csv`에서 Psum을 확인한다. Weight는 사람이 정한 예제다.
다음 셀부터 실제 학습된 체크포인트를 사용한다.
"""), cell("code", """# 2. 실행 환경 확인. Colab의 PyTorch는 그대로 사용한다.
import importlib.util
if importlib.util.find_spec('datasets') is None:
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'datasets'], check=True)
import torch
print('torch:', torch.__version__, 'device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')
"""), cell("markdown", """## E1·E2-A 실행

첫 이미지 정답·예측을 확인한 뒤 Test 10,000장 FP32 평가를 실행한다.
E2-A는 Train 1,000장 보정 + 겹치지 않는 Train 1,000장 설정 선택 후, 선택한 하나만 Test에 평가한다.
개발용 Train 집합은 체크포인트 학습 이력에 독립적인 검증 집합이 아니다.
Bias는 FP32이며 실제 정수 계수의 E2-B는 아직 미완료다. 허용 하락 폭을 정하지 않으면 자동 채택하지 않는다.
"""), cell("code", """# 3. 팀이 실행 전에 합의한 허용 하락 폭(%p). 미정이면 None 유지.
ACCEPT_DROP_PP = None
command = [sys.executable, '-m', 'model.run_reference', '--device', 'auto']
if ACCEPT_DROP_PP is not None:
    command += ['--accept-drop-pp', str(ACCEPT_DROP_PP)]
subprocess.run(command, check=True)
"""), cell("code", """# 4. 결과 읽기. 개발용 비교표와 최종 Test 결과를 구분한다.
import json
e1 = json.loads(Path('results/e1_fp32.json').read_text(encoding='utf-8'))
e2 = json.loads(Path('results/e2_ptq.json').read_text(encoding='utf-8'))
print('FP32 Test:', e1['fp32_top1'])
print('선택한 설정의 Test:', e2['selected_test'])
print('채택 판단:', e2['decision_input'])
"""), cell("markdown", """## 결과 저장

세션 종료 전에 ZIP을 다운로드한다. 실행자·날짜·출력과 설명 답안을 함께 제출한다.
다시 받은 소스로 바꾸려면 런타임을 새로 시작한다. 셀 재실행만으로 저장소를 자동 갱신하지 않는다.
"""), cell("code", """# 5. 결과와 Golden 파일 다운로드
import shutil
Path('results/golden_manifest.json').write_text(Path('golden/e1_sample0/manifest.json').read_text(encoding='utf-8'), encoding='utf-8')
with __import__('zipfile').ZipFile('e1_e2_outputs.zip', 'w') as z:
    for folder in ('results', 'golden'):
        for path in Path(folder).rglob('*'):
            if path.is_file(): z.write(path)
try:
    from google.colab import files
    files.download('e1_e2_outputs.zip')
except ImportError:
    print(Path('e1_e2_outputs.zip').resolve())
""")]
doc = dict(cells=cells, metadata={"accelerator": "GPU", "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"}}, nbformat=4, nbformat_minor=5)
for i, c in enumerate(cells): c["id"] = f"basic-{i:02d}"
Path('notebooks/E1_E2_resnet20_reference.ipynb').write_text(json.dumps(doc, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
