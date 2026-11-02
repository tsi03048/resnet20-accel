"""Verify recovered archive identity and original per-file hash records."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'historical/e12-e21'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def verify():
    manifest = json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))
    checked = 0
    for archive in manifest['archives']:
        file = ROOT / archive['path']
        assert sha(file.read_bytes()) == archive['sha256'], file
        with zipfile.ZipFile(file) as z:
            actual = {i.filename for i in z.infolist() if not i.is_dir()}
            assert actual == {e['path'] for e in archive['entries']}, file
            for item in archive['entries']:
                path = PurePosixPath(item['path'])
                assert not path.is_absolute() and '..' not in path.parts
                data = z.read(item['path'])
                assert len(data) == item['bytes'] and sha(data) == item['sha256'], path
            for exported in archive['exported']:
                assert (ROOT / exported['repository_path']).read_bytes() == z.read(exported['archive_path']), exported
            recorded = json.loads(z.read(archive['package'] + '/results/source_sha256.json'))
            for path, expected in recorded.items():
                data = z.read(archive['package'] + '/' + path.replace('\\', '/'))
                assert sha(data) == expected, (file, path)
                checked += 1
    return {'status': 'PASS', 'archives': len(manifest['archives']), 'original_hashes_checked': checked,
            'chapters': len(manifest['chapters']), 'new_rtl_simulation': False}

if __name__ == '__main__':
    print(json.dumps(verify(), indent=2))
