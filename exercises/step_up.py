"""Small, repeatable learning experiments. No GPU or dataset required."""
import argparse
import json
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

from exercises.conv_walkthrough import X, W, conv_trace
from quant.integer_math import rne_div, aligned_add


def experiment(lesson):
    if lesson == 'conv':
        base, trace = conv_trace()
        changed = deepcopy(X)
        changed[0][0] += 1
        actual, _ = conv_trace(changed)
        assert base == [10, 9, 8, 6] and actual == [11, 9, 8, 6]
        return {'before': base, 'after_X00_plus_1': actual,
                'first_psum': [r['psum'] for r in trace[:9]],
                'explain': 'X[0][0] belongs only to the first window; its weight is +1.'}
    if lesson == 'learn':
        x, target, w, b, lr = 2, 2, .5, .5, .1
        pred = max(0, w*x+b)
        loss = (pred-target)**2
        grad_w, grad_b = 2*(pred-target)*x, 2*(pred-target)
        new_w, new_b = w-lr*grad_w, b-lr*grad_b
        after = max(0, new_w*x+new_b)
        assert abs(new_w-.7) < 1e-9 and abs(new_b-.6) < 1e-9 and abs(after-2) < 1e-9
        return {'input': x, 'target': target, 'before': {'w': w, 'b': b, 'prediction': pred, 'loss': loss},
                'gradient': {'w': grad_w, 'b': grad_b}, 'learning_rate': lr,
                'after': {'w': new_w, 'b': new_b, 'prediction': after, 'loss': (after-target)**2},
                'explain': 'One educational regression update, not CIFAR training.'}
    if lesson == 'residual':
        x = [1, 2, 3, 4]
        h = [max(0, 2*v-3) for v in x]
        main = [-v+.5 for v in h]
        y = [max(0, a+b) for a, b in zip(main, x)]
        wrong = [max(0, max(0, a)+b) for a, b in zip(main, x)]
        assert y == [1.5, 1.5, .5, 0] and wrong != y
        return {'X': x, 'H': h, 'main': main, 'Y': y, 'wrong_extra_ReLU': wrong,
                'explain': 'Keep X until Add; preserve negative Conv2 contributions.'}
    if lesson == 'quant':
        rounding = {str(v/2): rne_div(v, 2) for v in [5, 7, -5, -7]}
        total = aligned_add(8, 4, 1, 2, 0)
        assert total == 16 and rounding['-2.5'] == -2
        return {'main_code': 8, 'main_scale': '1/8', 'skip_code': 4, 'skip_scale': '1/4',
                'wrong_raw_sum': 12, 'output_scale': '1/8', 'correct_code': total,
                'nearest_even': rounding, 'explain': 'Both paths represent 1.0; output represents 2.0.'}
    if lesson == 'handshake':
        rows = [dict(edge=i, valid=v, ready=r, data=d, fire=v*r)
                for i, (v, r, d) in enumerate([(1,0,'A'),(1,0,'A'),(1,1,'A'),
                                              (1,1,'B'),(0,1,None),(1,0,'C'),(1,1,'C')])]
        received = [r['data'] for r in rows if r['fire']]
        assert received == ['A','B','C']
        return {'edges': rows, 'received': received, 'explain': 'Count accepted edges, not cycles showing valid.'}
    raise ValueError(lesson)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('lesson', choices=['conv','learn','residual','quant','handshake','all'])
    p.add_argument('--out', default='results/learning/student_steps.json')
    args = p.parse_args()
    lessons = ['conv','learn','residual','quant','handshake'] if args.lesson == 'all' else [args.lesson]
    print('먼저 예측하세요. 실행 결과와 다른 이유를 한 문장으로 적어보세요.')
    report = {'executed_at_utc': datetime.now(timezone.utc).isoformat(),
              'evidence': 'EDUCATIONAL_PYTHON', 'fpga_measured': False,
              'lessons': {lesson: experiment(lesson) for lesson in lessons}}
    dest = Path(args.out)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report['lessons'], ensure_ascii=False, indent=2))
    print('PASS; record:', dest)


if __name__ == '__main__':
    main()
