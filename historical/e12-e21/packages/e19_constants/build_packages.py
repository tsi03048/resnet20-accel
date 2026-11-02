from pathlib import Path
import json,hashlib,shutil
from validate_package import CONTRACT,expected_files,validate
R=Path(__file__).resolve().parent;SOURCE=R/'source_e18'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
trusted={}
for name,c,h,case in [('small_compat',2,4,'small/job1'),('small_varied',2,4,'small/job4'),('stage12_varied',16,32,'stage12/job1'),('stage23_varied',32,16,'stage23/job1')]:
    p=R/'packages'/name;(p/'constants').mkdir(parents=True,exist_ok=True)
    m=dict(schema_version=1,target='e18_transition_diag_v1',shape=dict(cin=c,cout=2*c,h=h,w=h,oh=h//2,ow=h//2,stride1=2,stride2=1,pad=1),contract=CONTRACT,source=dict(kind='diagnostic',revision='e18_integrated',case=case,reference_generator_sha256=digest(SOURCE/'make_vectors.py')),files={})
    for role,(dtype,bits,shape,layout,axis) in expected_files(c,h).items():
        src=SOURCE/case/(role+'.hex');dst=p/'constants'/(role+'.hex');shutil.copyfile(src,dst)
        m['files'][role]=dict(path='constants/'+role+'.hex',logical_dtype=dtype,storage_bits=bits,shape=shape,layout=layout,output_channel_axis=axis,encoding='hex_lines_twos_complement',word_order='logical_row_major',count=__import__('math').prod(shape),size_bytes=dst.stat().st_size,sha256=digest(dst))
    (p/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');trusted[name]=digest(p/'manifest.json')
    print(json.dumps(validate(p,trusted[name])))
(R/'expected_manifests.json').write_text(json.dumps(trusted,indent=2)+'\n')
