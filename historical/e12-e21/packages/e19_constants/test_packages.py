from pathlib import Path
import copy,hashlib,json,shutil,tempfile
from validate_package import validate,InvalidPackage
from prepare_preload import prepare
R=Path(__file__).resolve().parent;base=R/'packages/small_varied'
pins=json.loads((R/'expected_manifests.json').read_text());report={'positive':[],'rejections':[],'known_limitations':[]}
for name,digest in pins.items():
    report['positive'].append(validate(R/'packages'/name,digest))
    prepare(R/'packages'/name,R/'preloads'/(name+'.json'),digest)
def run(name,mutate,expected,pin=False):
    with tempfile.TemporaryDirectory(prefix='e19-') as td:
        p=Path(td)/'pkg';shutil.copytree(base,p);m=json.loads((p/'manifest.json').read_text());mutate(p,m)
        (p/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
        try:validate(p,pins['small_varied'] if pin else None)
        except InvalidPackage as e:
            assert e.code==expected,(name,e.code,expected,str(e));report['rejections'].append({'name':name,'code':e.code});return
        raise AssertionError('accepted '+name)
def set_field(path,value):
    def mutate(p,m):
        x=m
        for k in path[:-1]:x=x[k]
        x[path[-1]]=value
    return mutate
def edit_hex(role,fn,rehash=True):
    def mutate(p,m):
        f=p/m['files'][role]['path'];fn(f)
        if rehash:m['files'][role]['size_bytes']=f.stat().st_size;m['files'][role]['sha256']=hashlib.sha256(f.read_bytes()).hexdigest()
    return mutate
cases=[('version',['schema_version'],2,'VERSION'),('bool_version',['schema_version'],True,'VERSION'),('target',['target'],'other','TARGET'),('rounding',['contract','rounding'],'truncate','CONTRACT'),('zero',['contract','zero_point'],5,'CONTRACT'),('bool_zero',['contract','zero_point'],False,'CONTRACT'),('boundary',['contract','conv2'],'wide_acc_no_clip','CONTRACT'),('shape',['shape','cout'],8,'SHAPE'),('bool_stride',['shape','stride2'],True,'SHAPE'),('axis',['files','weight1','output_channel_axis'],1,'AXIS'),('layout',['files','weight1','layout'],'HWIO','AXIS'),('dtype',['files','weight1','logical_dtype'],'uint8','DTYPE'),('storage',['files','bias1','storage_bits'],8,'DTYPE'),('count',['files','n1','count'],3,'COUNT'),('file_shape',['files','n1','shape'],[2,2],'FILE_SHAPE'),('size',['files','n1','size_bytes'],1,'SIZE'),('traversal',['files','n1','path'],'constants/../n1.hex','PATH'),('absolute',['files','n1','path'],'/tmp/n1.hex','PATH'),('source_kind',['source','kind'],'trained_checkpoint','SOURCE')]
for name,path,value,code in cases:run(name,set_field(path,value),code)
run('missing_role',lambda p,m:m['files'].pop('sa'),'ROLES')
run('missing_file',lambda p,m:(p/m['files']['n1']['path']).unlink(),'FILE_PATH')
def replace_first(f,value):
    a=f.read_text().splitlines();a[0]=value;f.write_text('\n'.join(a)+'\n')
run('bit_changed',edit_hex('n1',lambda f:replace_first(f,'000000ff'),False),'HASH')
run('multiplier_range',edit_hex('n1',lambda f:replace_first(f,'00010000')),'RANGE')
run('shift_range',edit_hex('s1',lambda f:replace_first(f,'00000020')),'RANGE')
run('hex_syntax',edit_hex('n1',lambda f:replace_first(f,'000000zz')),'HEX')
run('hex_width',edit_hex('n1',lambda f:replace_first(f,'1')),'HEX')
run('short_file',edit_hex('n1',lambda f:f.write_text('\n'.join(f.read_text().splitlines()[1:])+'\n')),'ELEMENT_COUNT')
run('acc_bound',edit_hex('bias1',lambda f:replace_first(f,'7fffffff')),'ACC_BOUND')
run('coherent_edit_with_pin',edit_hex('n1',lambda f:replace_first(f,'00000004')),'MANIFEST_HASH',True)
with tempfile.TemporaryDirectory(prefix='e19-') as td:
    p=Path(td)/'pkg';shutil.copytree(base,p)
    original=(p/'manifest.json').read_text();(p/'manifest.json').write_text(original.replace('"schema_version": 1','"schema_version": 1, "schema_version": 1'))
    try:validate(p)
    except InvalidPackage as e:assert e.code=='JSON_DUPLICATE';report['rejections'].append({'name':'duplicate_key','code':e.code})
    else:raise AssertionError('duplicate key accepted')
with tempfile.TemporaryDirectory(prefix='e19-') as td:
    p=Path(td)/'pkg';shutil.copytree(base,p);m=json.loads((p/'manifest.json').read_text())
    # A consistent content+hash edit is structurally legal without an external pin.
    edit_hex('n1',lambda f:replace_first(f,'00000004'))(p,m);(p/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    validate(p);report['known_limitations'].append('coherent_content_and_manifest_edit_passes_without_external_pin')
    output=Path(td)/'preload.json';output.write_text('previous valid snapshot')
    try:prepare(p,output,pins['small_varied'])
    except InvalidPackage as e:assert e.code=='MANIFEST_HASH' and output.read_text()=='previous valid snapshot'
    else:raise AssertionError('invalid prepare wrote output')
report['snapshot_failure_preserves_existing_output']=True
(R/'results/validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS packages=',len(report['positive']),'negative_rejections=',len(report['rejections']),'pinned_prepare_failure_preserves_output=True')
