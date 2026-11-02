"""Emit a software preload snapshot only after validation against an externally pinned digest."""
from pathlib import Path
import json,sys,tempfile,os
from validate_package import validate,InvalidPackage
def prepare(package,dest,pinned_digest):
    result=validate(package,pinned_digest,include_values=True)
    dest=Path(dest);dest.parent.mkdir(parents=True,exist_ok=True)
    # Use the already-validated values in memory; don't reopen the hex files.
    fd,tmp=tempfile.mkstemp(prefix='.preload-',dir=dest.parent)
    try:
        with os.fdopen(fd,'w') as f:json.dump(result,f,indent=2);f.write('\n')
        os.replace(tmp,dest)
    finally:
        if Path(tmp).exists():Path(tmp).unlink()
    return {k:v for k,v in result.items() if k!='values'}
if __name__=='__main__':
    try:
        if len(sys.argv)!=4:raise InvalidPackage('USAGE','python3 prepare_preload.py PACKAGE OUTPUT_JSON TRUSTED_MANIFEST_SHA256')
        print(json.dumps(prepare(*sys.argv[1:]),indent=2))
    except InvalidPackage as e:
        print(json.dumps(dict(status='REJECT',code=e.code,detail=str(e))));sys.exit(1)
