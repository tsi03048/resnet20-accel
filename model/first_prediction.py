"""Run one real image before attempting full-dataset evaluation."""
import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device', choices=['cpu','cuda','auto'], default='cpu')
    p.add_argument('--out', default='results/learning/first_prediction')
    args = p.parse_args()
    import numpy as np
    import torch
    from PIL import Image
    from model.common import load_resnet20, fetch_reference, MEAN, STD, CLASSES
    torch.set_num_threads(min(8, torch.get_num_threads()))
    device = ('cuda' if torch.cuda.is_available() else 'cpu') if args.device == 'auto' else args.device
    ref = Path('third_party/pytorch_resnet_cifar10')
    # The bundled model source is sufficient; a Git checkout is not required.
    if not (ref/'resnet.py').exists():
        ref = Path(fetch_reference())
    sys.path.insert(0, str(ref.resolve()))
    model, info = load_resnet20(str(ref), device)
    golden = Path('reference/learning_sample0')
    manifest = json.loads((golden/'manifest.json').read_text(encoding='utf-8'))
    input_path = golden/'input.npz'
    if hashlib.sha256(input_path.read_bytes()).hexdigest() != manifest['input_npz_sha256']:
        raise ValueError('Sample input hash mismatch')
    with np.load(input_path, allow_pickle=False) as bundle:
        x = bundle['input']
    source = (ref/'resnet.py').read_bytes().replace(b'\r\n', b'\n')
    if hashlib.sha256(source).hexdigest() != manifest['resnet_source_lf_sha256']:
        raise ValueError('Reference model source hash mismatch')
    if x.shape != (1,3,32,32) or x.dtype != np.float32:
        raise ValueError('Sample input shape/dtype mismatch')
    with torch.no_grad():
        scores = model(torch.from_numpy(x).to(device)).cpu().numpy()[0]
    pred = int(np.argmax(scores))
    dest = Path(args.out)
    dest.mkdir(parents=True, exist_ok=True)
    rgb = np.rint(np.clip((x[0].transpose(1,2,0)*np.array(STD)+np.array(MEAN))*255, 0, 255)).astype('uint8')
    Image.fromarray(rgb).resize((256,256), Image.Resampling.NEAREST).save(dest/'image.png')
    report = {'executed_at_utc': datetime.now(timezone.utc).isoformat(), 'test_images': 1,
              'sample_index': manifest['sample_index'], 'label': manifest['label_name'],
              'prediction': CLASSES[pred], 'prediction_index': pred, 'logits_shape': [1,10],
              'classes': list(CLASSES), 'logits': scores.tolist(), 'device': device,
              'input_sha256': hashlib.sha256(input_path.read_bytes()).hexdigest(),
              'checkpoint_sha256': info['checkpoint_sha256'],
              'source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'evidence': 'SINGLE_IMAGE_FP32_INFERENCE', 'full_test_accuracy': None,
              'note': 'One frozen real CIFAR-10 input; no dataset accuracy estimate.'}
    (dest/'prediction.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('image:', dest/'image.png')
    print('label:', report['label'], 'prediction:', report['prediction'], 'logits: [1,10]')
    print('1 image only. Full Test accuracy is not measured here.')


if __name__ == '__main__':
    main()
