"""Optional provenance check against the original cached Test Arrow (no download)."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from quant.e2b_reference import IntegerReference,load_package,array_hash

def verify(path):
    from datasets import Dataset
    from model.common import eval_transform
    root=Path('reference/e2b_v1/full_vectors');meta=json.loads((root/'sample1_source.json').read_text())
    digest=hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(1<<20),b''):digest.update(chunk)
    if digest.hexdigest()!=meta['source_arrow_sha256']:raise ValueError('Original Arrow hash differs')
    ds=Dataset.from_file(str(path));m,a=load_package('reference/e2b_v1');ref=IntegerReference(m,a,'numpy');transform=eval_transform()
    with np.load('reference/e2b_v1/sample0/tensors.npz',allow_pickle=False) as z:old=z['input'].copy()
    for i in (0,1):
        row=ds[i];rgb=row['img'].convert('RGB');q=ref.quantize_input(transform(rgb).unsqueeze(0).numpy())
        if i==0:
            if not np.array_equal(q,old):raise ValueError('sample0 preprocessing mismatch')
        else:
            if int(row['label'])!=meta['label'] or hashlib.sha256(np.asarray(rgb).tobytes()).hexdigest()!=meta['image_rgb_sha256'] or array_hash(q)!=meta['input_array_sha256']:raise ValueError('sample1 source/input mismatch')
            raw=''.join(f'{int(v)&255:02x}\n' for v in q.reshape(-1)).encode('ascii')
            if raw!=(root/'sample1_input.hex').read_bytes():raise ValueError('sample1 input byte mismatch')
    return dict(status='PASS',test_indices=[0,1],sample0_matches_frozen_input=True,sample1_label=meta['label'],arrow_sha256=digest.hexdigest())

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('arrow',type=Path);args=p.parse_args();print(json.dumps(verify(args.arrow),indent=2))
