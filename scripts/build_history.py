"""Deterministic EMR source ZIP and extracted SDK archive; install SDK separately."""
from pathlib import Path
import zipfile


def archive(output, files):
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(files.items()):
            entry=zipfile.ZipInfo(name,(2020,1,1,0,0,0));entry.create_system=3;entry.external_attr=0o644<<16
            # STORED avoids platform compression differences, including SDK data files.
            z.writestr(entry,data)


def build(root):
    out=root/'artifacts';out.mkdir(exist_ok=True)
    sources={'src/__init__.py':b'', 'src/silver/__init__.py':b'',
             'src/silver/transform.py':(root/'src/silver/transform.py').read_bytes().replace(b'\r\n',b'\n')}
    archive(out/'history-libs.zip',sources)
    deps=root/'local/history-sdk'
    if not (deps/'boto3/__init__.py').exists(): raise ValueError('Install scripts/requirements-history.txt into local/history-sdk first')
    # Console entrypoints embed the host Python path and are not used by workers.
    files={p.relative_to(deps).as_posix():p.read_bytes() for p in deps.rglob('*') if p.is_file() and 'bin' not in p.relative_to(deps).parts and '__pycache__' not in p.parts and not p.name.endswith('.pyc') and ('.dist-info' not in str(p.parent) or p.name.lower().startswith(('license', 'notice', 'copying')))}
    archive(out/'history-sdk.zip',files)
    (out/'history-job.py').write_bytes((root/'src/history/job.py').read_bytes().replace(b'\r\n',b'\n'))


if __name__=='__main__':
    build(Path(__file__).resolve().parents[1]);print('EMR artifacts built in ignored artifacts/')
