"""Strict validator for the explicitly supported E18 diagnostic contract, not arbitrary models."""
from pathlib import Path,PurePosixPath
import hashlib,json,math,re,sys
CONTRACT={"rounding":"RNE_ties_to_even","zero_point":0,"conv1":"requant_relu_sat8","conv2":"requant_sat8_store_M","add":"int8_M_and_OptionA_wide_sum_one_RNE_relu_sat8","snapshot":"whole_tables_at_block_command"}
class InvalidPackage(ValueError):
    def __init__(self,code,detail):super().__init__(detail);self.code=code
def require(ok,code,detail):
    if not ok:raise InvalidPackage(code,detail)
def unique_object(pairs):
    out={}
    for k,v in pairs:
        require(k not in out,'JSON_DUPLICATE',k);out[k]=v
    return out
def load_json(path,raw=None):
    def bad_constant(x):raise InvalidPackage('JSON_NUMBER',x)
    try:return json.loads(raw.decode('utf-8') if raw is not None else Path(path).read_text(),object_pairs_hook=unique_object,parse_constant=bad_constant)
    except InvalidPackage:raise
    except (OSError,ValueError,UnicodeError) as e:raise InvalidPackage('JSON_READ',str(e)) from e
def expected_files(c,h):
    d=2*c
    out={}
    for i,cin in [(1,c),(2,d)]:
        out[f'weight{i}']=('int8',8,[d,cin,3,3],'OIHW',0)
        out[f'bias{i}']=('int32',32,[d],'O',0)
    for role in ['n1','n2','nm','ns']:out[role]=('uint16',32,[d],'O',0)
    for role in ['s1','s2','sa']:out[role]=('uint5',32,[d],'O',0)
    return out
def validate(root,expected_manifest_sha256=None,include_values=False):
    root=Path(root).resolve();mp=root/'manifest.json'
    try:manifest_bytes=mp.read_bytes()
    except OSError as e:raise InvalidPackage('JSON_READ',str(e)) from e
    manifest_digest=hashlib.sha256(manifest_bytes).hexdigest()
    if expected_manifest_sha256 is not None:
        require(type(expected_manifest_sha256)==str and re.fullmatch('[0-9a-f]{64}',expected_manifest_sha256) is not None,'TRUST_FORMAT','manifest digest')
        require(manifest_digest==expected_manifest_sha256,'MANIFEST_HASH','manifest identity differs')
    m=load_json(mp,manifest_bytes)
    require(type(m)==dict,'SCHEMA','object required')
    require(type(m.get('schema_version'))==int and m['schema_version']==1,'VERSION','schema1 only')
    require(m.get('target')=='e18_transition_diag_v1','TARGET','unsupported RTL target')
    require(m.get('contract')==CONTRACT and type(m['contract'].get('zero_point'))==int,'CONTRACT','rounding/zero/boundary/snapshot mismatch')
    dims=m.get('shape');require(type(dims)==dict,'SHAPE','shape object')
    c,h=dims.get('cin'),dims.get('h')
    require(type(c)==int and type(h)==int and (c,h) in [(2,4),(16,32),(32,16)],'SHAPE','unsupported Cin/H')
    require(all(type(v)==int for v in dims.values()) and dims==dict(cin=c,cout=2*c,h=h,w=h,oh=h//2,ow=h//2,stride1=2,stride2=1,pad=1),'SHAPE','inconsistent shape')
    source=m.get('source');require(type(source)==dict and source.get('kind')=='diagnostic' and source.get('revision')=='e18_integrated','SOURCE','diagnostic lineage only')
    require(type(source.get('case'))==str and re.fullmatch(r'(small|stage12|stage23)/job\d+',source['case']) is not None,'SOURCE','invalid source case')
    expected_group={(2,4):'small',(16,32):'stage12',(32,16):'stage23'}[(c,h)]
    require(source['case'].split('/')[0]==expected_group,'SOURCE','source shape differs')
    require(type(source.get('reference_generator_sha256'))==str and re.fullmatch('[0-9a-f]{64}',source['reference_generator_sha256']) is not None,'SOURCE','generator digest required')
    fs=m.get('files');spec=expected_files(c,h)
    require(type(fs)==dict and set(fs)==set(spec),'ROLES','exact eleven roles required')
    parsed={};seen=set();total=0
    for role,(dtype,bits,shape,layout,axis) in spec.items():
        e=fs[role];require(type(e)==dict,'FILE_META',role)
        require(e.get('logical_dtype')==dtype and type(e.get('storage_bits'))==int and e['storage_bits']==bits,'DTYPE',role)
        require(e.get('shape')==shape and all(type(v)==int for v in e.get('shape',[])),'FILE_SHAPE',role)
        require(e.get('layout')==layout and type(e.get('output_channel_axis'))==int and e['output_channel_axis']==axis,'AXIS',role)
        require(e.get('encoding')=='hex_lines_twos_complement' and e.get('word_order')=='logical_row_major','ENCODING',role)
        count=math.prod(shape);require(type(e.get('count'))==int and e['count']==count,'COUNT',role)
        rel=e.get('path');require(type(rel)==str and '\\' not in rel,'PATH',role)
        rp=PurePosixPath(rel)
        require(not rp.is_absolute() and '..' not in rp.parts and '.' not in rel.split('/') and rp.parts and rp.parts[0]=='constants','PATH',role)
        require(str(rp)==rel and rel not in seen,'PATH','duplicate or noncanonical '+role);seen.add(rel)
        p=root/rel;require(p.resolve()==p and p.is_file(),'FILE_PATH','missing/symlink '+role)
        try:data=p.read_bytes()
        except OSError as ex:raise InvalidPackage('FILE_READ',str(ex)) from ex
        require(type(e.get('size_bytes'))==int and e['size_bytes']==len(data),'SIZE',role)
        require(e.get('sha256')==hashlib.sha256(data).hexdigest(),'HASH',role)
        try:lines=data.decode('ascii').splitlines()
        except UnicodeError as ex:raise InvalidPackage('HEX','not ASCII '+role) from ex
        require(len(lines)==count,'ELEMENT_COUNT',role)
        pattern='[0-9a-f]{'+str(bits//4)+'}'
        require(all(re.fullmatch(pattern,x) is not None for x in lines),'HEX','word width/syntax '+role)
        vals=[int(x,16) for x in lines]
        if dtype=='uint16':require(all(x<=65535 for x in vals),'RANGE',role)
        if dtype=='uint5':require(all(x<=31 for x in vals),'RANGE',role)
        if dtype.startswith('int'):vals=[x-(1<<bits) if x&(1<<(bits-1)) else x for x in vals]
        parsed[role]=vals;total+=count
    # E18 bias is added before products; conservative all-prefix signed8 MAC bound.
    for i,cin in [(1,c),(2,2*c)]:
        k=cin*9;w=parsed[f'weight{i}'];bias=parsed[f'bias{i}']
        for co in range(2*c):
            bound=128*sum(abs(x) for x in w[co*k:(co+1)*k])
            require(-(1<<31)<=bias[co]-bound and bias[co]+bound<(1<<31),'ACC_BOUND',f'conv{i} channel{co}')
    result=dict(status='PASS',target=m['target'],source_case=source['case'],files=len(spec),elements=total,manifest_sha256=manifest_digest)
    if include_values:result['values']=parsed
    return result
if __name__=='__main__':
    try:
        require(len(sys.argv) in [2,3],'USAGE','python3 validate_package.py PACKAGE [TRUSTED_MANIFEST_SHA256]')
        print(json.dumps(validate(sys.argv[1],sys.argv[2] if len(sys.argv)==3 else None),indent=2))
    except InvalidPackage as e:
        print(json.dumps(dict(status='REJECT',code=e.code,detail=str(e)),indent=2));sys.exit(1)
