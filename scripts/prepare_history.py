"""Download and prepare ONE complete year locally. Does not access AWS."""
import argparse
import json
from pathlib import Path
import sys
from urllib.parse import urlencode
from urllib.request import Request, urlopen
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from src.history.prepare import checked_year, prepare_b3, prepare_rates, digest, MAX_ZIP


def download(url, path, cap):
    tmp = path.with_suffix(path.suffix + '.partial')
    try:
        with urlopen(Request(url, headers={'User-Agent': 'b3-lakehouse-aws/0.1'}), timeout=60) as response, tmp.open('wb') as stream:
            if not response.geturl().startswith('https://'): raise ValueError('Insecure redirect')
            size = 0
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                size += len(chunk)
                if size > cap: raise ValueError('Download exceeds cap')
                stream.write(chunk)
        tmp.replace(path)
    finally:
        tmp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--year', type=int, default=2025)
    args = parser.parse_args(); year = checked_year(args.year)
    root = Path(__file__).resolve().parents[1] / 'local' / f'history-{year}'
    # Never mix leftover monthly files from an earlier preparation.
    if root.exists(): raise ValueError('Preparation directory already exists; review it before reusing')
    root.mkdir(parents=True)
    urls = {'b3': f'https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A{year}.ZIP'}
    raw = root / 'raw.zip'; download(urls['b3'], raw, MAX_ZIP)
    checked = prepare_b3(raw, year, root)
    rates = {}
    query = urlencode({'formato':'json','dataInicial':f'01/01/{year}','dataFinal':f'31/12/{year}'})
    for series, code in [('cdi',12),('selic',11),('usd_brl_sell',1)]:
        urls[series] = f'https://api.bcb.gov.br/dados/serie/bcdata.sgs.{code}/dados?{query}'
        path = root / f'{series}.json'; download(urls[series], path, 1024 * 1024); rates[series] = path.read_bytes()
    checked['rate_rows'] = prepare_rates(rates, year, checked['days'], root / 'rates.jsonl')
    files = [{'name':p.name, 'bytes':p.stat().st_size, 'sha256':digest(p)} for p in sorted(root.iterdir()) if p.is_file()]
    manifest = {'version':1, 'year':year, 'sources':urls, 'files':files, **checked}
    (root / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps({'year':year, 'raw_rows':checked['raw_rows'], 'scoped_rows':checked['scoped_rows'], 'rate_rows':checked['rate_rows'], 'files':len(files)}))


if __name__ == '__main__': main()
