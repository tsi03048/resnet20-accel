import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
allowed = ['model', 'quant', 'exercises', 'tests', 'tools', 'docs', 'notebooks', 'rtl', 'tb', 'board', '.github']
paths = [root / 'README.md', root / 'requirements.txt', root / '.gitignore']
for folder in allowed:
    paths += [p for p in (root / folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
paths += [p for p in (root / 'results').glob('*.json')]
paths += [p for p in (root / 'results/basic').glob('*') if p.is_file()]
paths += list((root / 'golden').rglob('*.json'))
paths += [root / 'golden/README.md']
print(json.dumps({p.relative_to(root).as_posix(): p.read_text(encoding='utf-8') for p in paths}, ensure_ascii=False))
