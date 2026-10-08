from pathlib import Path
import zipfile
from scripts.build_history import build


def test_emr_package_contains_only_sources_and_extractable_sdk(tmp_path):
    results=[]
    for label,ending in [('linux',b'\n'),('windows',b'\r\n')]:
        root=tmp_path/label
        for name in ['src/silver/transform.py','src/history/job.py']:
            p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'value=1'+ending)
        for name,body in [('boto3/__init__.py',b'__version__="test"\n'),('botocore/data/s3/model.json',b'{"model":"test"}')]:
            p=root/'local/history-sdk'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
        console=root/'local/history-sdk/bin/jp.py';console.parent.mkdir(parents=True);console.write_bytes(label.encode()+b' host interpreter'+ending)
        build(root)
        out=root/'artifacts'
        with zipfile.ZipFile(out/'history-sdk.zip') as z:
            assert 'botocore/data/s3/model.json' in z.namelist()
            assert 'bin/jp.py' not in z.namelist()
            assert all(not n.startswith('/') and '..' not in Path(n).parts for n in z.namelist())
        results.append(tuple((out/n).read_bytes() for n in ['history-sdk.zip','history-libs.zip','history-job.py']))
    assert results[0]==results[1]
