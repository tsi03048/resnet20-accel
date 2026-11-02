"""Create the beginner E2-B notebook with offline replay first."""
import json
from pathlib import Path


def cell(kind, text, i):
    d=dict(cell_type=kind, metadata={}, id=f"e2b-{i:02d}", source=text.splitlines(keepends=True))
    if kind=="code": d.update(execution_count=None, outputs=[])
    return d


texts=[("markdown", """# E2-B — 실제 정수 기준을 한 장부터 확인하기

먼저 배포한 실제 모델 상수·정수 입력을 읽어 **61개 경계의 code가 같은지** 확인한다.
첫 실습에는 NumPy만 필요하며 GPU·CIFAR 전체 다운로드가 필요 없다.
[설명과 계약](https://github.com/tsi03048/resnet20-accel/blob/main/docs/e2b_integer_reference.md)
전체 정확도 재평가는 뒤의 선택 셀에서 실행한다. 현재 E2-B 정수 backend는 CPU를 사용한다.
"""), ("code", """# 0. E1/E2-A 실습 폴더와 분리해 준비한다.
import os, sys, subprocess, json, importlib.util
from pathlib import Path
repo=Path('/content/resnet20-accel-e2b') if Path('/content').is_dir() else Path.cwd() / 'resnet20-accel-e2b'
if not repo.exists():
    subprocess.run(['git','clone','https://github.com/tsi03048/resnet20-accel.git',str(repo)],check=True)
os.chdir(repo)
if not Path('quant/replay_e2b.py').exists():
    raise RuntimeError('이 폴더는 이전 버전입니다. 작업을 저장하고 새 런타임/폴더에서 다시 시작하세요.')
sys.path.insert(0,str(repo))
if importlib.util.find_spec('numpy') is None:
    subprocess.run([sys.executable,'-m','pip','install','numpy'],check=True)
subprocess.run(['git','rev-parse','HEAD'],check=True)
"""), ("code", """# 1. 파일 검사를 통과한 상수와 입력으로 실제 정수 계산
from quant.replay_e2b import replay
from datetime import datetime, timezone
result=replay(backend='numpy')
result['executed_at_utc']=datetime.now(timezone.utc).isoformat()
Path('results/e2b_student_replay.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
"""), ("markdown", """정상 결과: PASS / 61경계 / 552,084원소 / prediction 3 / cat.
이것은 소프트웨어 Golden 재현이며 RTL·보드 통과가 아니다.
"""), ("code", """# 2. 실제 Stem 첫 원소를 따라가기
import numpy as np
from quant.integer_math import rne_div
with np.load('reference/e2b_v1/constants.npz',allow_pickle=False) as z:
    bias=int(z['stem.bias'][0]); n=int(z['stem.multiplier'][0]); shift=int(z['stem.shift'][0])
with np.load('reference/e2b_v1/sample0/tensors.npz',allow_pickle=False) as z:
    acc=int(z['stem.acc'][0,0,0,0]); expected=int(z['stem'][0,0,0,0])
code=min(127,max(0,rne_div(acc*n,1<<shift)))
print('곱의 합:',acc-bias,'Bias:',bias,'acc:',acc,'N:',n,'shift:',shift)
print('직접 계산:',code,'Golden:',expected)
if code!=expected: raise RuntimeError('첫 Stem code 불일치')
"""), ("markdown", """## 선택: 상수부터 재생성하고 Test 10,000장 평가

아래 `RUN_FULL`을 True로 바꾸면 체크포인트·CIFAR 데이터를 받고 전체 평가한다.
배포한 E2-A 출처를 고정해 읽으며 새로 선택하지 않는다. CPU에서 시간이 걸린다.
빠른 16장 점검은 전체 정확도 결과로 제출하지 않는다.
"""), ("code", """RUN_FULL=False
if RUN_FULL:
    if any(importlib.util.find_spec(p) is None for p in ('torch','torchvision','datasets')):
        subprocess.run([sys.executable,'-m','pip','install','-r','requirements.txt'],check=True)
    subprocess.run([sys.executable,'-m','quant.run_e2b','--limit','10000','--audit','8','--batch-size','32'],check=True)
    print(Path('results/e2b_integer.json').read_text(encoding='utf-8'))
else:
    print('한 장 재현만 실행했습니다. results/e2b_integer.json은 저장소에 배포된 기준 실행 기록입니다.')
"""), ("markdown", """## 제출

실행자·날짜·패키지 hash·실행한 범위·첫 Stem 계산·확인 질문 답안을 함께 제출한다.
ZIP에는 저장소의 기존 결과도 들어 있다. 본인 실행은 `e2b_student_replay.json`,
전체 실행은 `e2b_run_manifest.json`의 시간·인자로 구분한다.
"""), ("code", """# 3. 결과·상수·Golden 보관
from zipfile import ZipFile, ZIP_DEFLATED
with ZipFile('e2b_outputs.zip','w',ZIP_DEFLATED) as z:
    for folder in ('reference/e2b_v1','results','artifacts/e2b_v1','golden/e2b_sample0'):
        for path in Path(folder).rglob('*'):
            if path.is_file(): z.write(path)
try:
    from google.colab import files
    files.download('e2b_outputs.zip')
except ImportError:
    print(Path('e2b_outputs.zip').resolve())
""")]
doc=dict(cells=[cell(k,t,i) for i,(k,t) in enumerate(texts)],
         metadata={"kernelspec":{"name":"python3","language":"python","display_name":"Python 3"}},nbformat=4,nbformat_minor=5)
Path('notebooks/E2B_integer_reference.ipynb').write_text(json.dumps(doc,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
