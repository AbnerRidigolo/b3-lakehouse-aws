"""Publish prepared 2025 bronze through official AWS CLI. Run only after approval."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from src.history.prepare import digest


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--account-id',required=True);p.add_argument('--profile',default='b3-dev');p.add_argument('--aws-cli',default=r'C:\Program Files\Amazon\AWSCLIV2\aws.exe');a=p.parse_args()
    def call(args,missing_ok=False):
        r=subprocess.run([a.aws_cli,*args,'--profile',a.profile,'--region','us-east-1','--output','json','--no-cli-pager'],text=True,capture_output=True)
        if r.returncode:
            if missing_ok and any(x in r.stderr for x in ['(404)','(NoSuchKey)','(NotFound)']):return None
            raise RuntimeError(r.stderr)
        return json.loads(r.stdout) if r.stdout.strip() else {}
    assert call(['sts','get-caller-identity'])['Account']==a.account_id
    root=Path(__file__).resolve().parents[1]/'local/history-2025'
    raw=(root/'manifest.json').read_bytes();manifest=json.loads(raw);assert manifest['year']==2025
    files=manifest['files']+[{'name':'manifest.json','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}]
    bucket=f'b3-lakehouse-aws-bronze-{a.account_id}'
    # Validate every local payload before any writes; reject unexpected paths.
    for f in files:
        if Path(f['name']).name!=f['name'] or f['name'] in ['.','..']:raise ValueError('Unsafe manifest path')
        path=root/f['name']
        if path.stat().st_size!=f['bytes'] or digest(path)!=f['sha256']:raise ValueError('Prepared payload changed')
    for f in files:
        key='bronze/history/year=2025/'+f['name'];prior=call(['s3api','head-object','--bucket',bucket,'--key',key],missing_ok=True)
        if prior:
            if prior.get('Metadata',{}).get('sha256')!=f['sha256'] or prior['ContentLength']!=f['bytes']:raise ValueError('Conflicting historical bronze object')
        else:
            call(['s3api','put-object','--bucket',bucket,'--key',key,'--body',str(root/f['name']),'--if-none-match','*','--server-side-encryption','AES256','--metadata',json.dumps({'sha256':f['sha256'],'year':'2025'}),'--tagging','Project=b3-lakehouse-aws'])
    # Publish SUCCESS last. A failed upload can be resumed without overwriting objects.
    item={'pk':{'S':'bronze#year=2025'},'status':{'S':'SUCCESS'},'manifest_sha256':{'S':hashlib.sha256(raw).hexdigest()},'scoped_rows':{'N':str(manifest['scoped_rows'])},'rate_rows':{'N':str(manifest['rate_rows'])}}
    call(['dynamodb','put-item','--table-name','b3-lakehouse-aws-bronze-runs','--item',json.dumps(item),'--condition-expression','attribute_not_exists(manifest_sha256) OR manifest_sha256 = :hash','--expression-attribute-values',json.dumps({':hash':item['manifest_sha256']})])
    print('Historical bronze SUCCESS: 18 immutable objects for 2025; no EMR job started.')


if __name__=='__main__':main()
