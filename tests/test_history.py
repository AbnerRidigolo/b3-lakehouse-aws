from datetime import date
import io
import json
import zipfile
import pytest
from src.history.prepare import prepare_b3,prepare_rates,checked_year
from scripts.history_request import request
from src.history.job import options


def annual(tmp_path,year=2025,footer=3,member=None,row_year=None):
    head=bytearray(b' '*245);head[:2]=b'00';head[2:15]=f'COTAHIST.{year}'.encode();head[15:23]=b'BOVESPA '
    row=bytearray(b' '*245);row[:2]=b'01';row[2:10]=f'{row_year or year}1001'.encode();row[10:12]=b'02';row[24:27]=b'010'
    tail=bytearray(head);tail[:2]=b'99';tail[31:42]=f'{footer:011d}'.encode()
    p=tmp_path/'annual.zip'
    with zipfile.ZipFile(p,'w') as z:z.writestr(member or f'COTAHIST_A{year}.TXT',b'\r\n'.join([head,row,tail])+b'\r\n')
    return p


def test_streamed_annual_footer_and_month_partition(tmp_path):
    m=prepare_b3(annual(tmp_path),2025,tmp_path/'out')
    assert m['scoped_rows']==1 and m['days']=={'2025-10-01':1} and m['trailer_count_mode']=='all_records'
    assert len((tmp_path/'out/quotes-10.txt').read_text().splitlines())==1
    assert prepare_b3(annual(tmp_path,footer=1),2025,tmp_path/'other')['trailer_count_mode']=='quotes_only'


@pytest.mark.parametrize('kwargs',[{'footer':7},{'member':'../../file.txt'},{'row_year':2024}])
def test_wrong_counts_member_or_year_blocks_preparation(tmp_path,kwargs):
    with pytest.raises(ValueError):prepare_b3(annual(tmp_path,**kwargs),2025,tmp_path/'out')


def test_rates_require_all_series_and_trading_day_coverage(tmp_path):
    raw=json.dumps([{'data':'01/10/2025','valor':'0.05'}]).encode();inputs={n:raw for n in ['cdi','selic','usd_brl_sell']}
    assert prepare_rates(inputs,2025,['2025-10-01'],tmp_path/'rates')==3
    with pytest.raises(ValueError,match='coverage'):prepare_rates(inputs,2025,['2025-10-02'],tmp_path/'rates')
    inputs['cdi']=json.dumps([{'data':'01/10/2025','valor':'0.05'},{'data':'01/10/2025','valor':'0.06'}]).encode()
    with pytest.raises(ValueError,match='Conflicting'):prepare_rates(inputs,2025,[],tmp_path/'rates')


def test_incomplete_year_and_unbounded_request_rejected():
    with pytest.raises(ValueError):checked_year(date.today().year)
    a=request('00test','123456789012','a'*64);b=request('00test','123456789012','a'*64)
    assert a['clientToken']==b['clientToken'] and a['executionTimeoutMinutes']==15 and a['retryPolicy']['maxAttempts']==1
    conf=a['jobDriver']['sparkSubmit']['sparkSubmitParameters']
    assert 'spark.dynamicAllocation.enabled=false' in conf and 'spark.executor.instances=1' in conf
    with pytest.raises(ValueError):request('appid;command','123456789012','a'*64)


def test_glue_framework_arguments_do_not_change_pinned_data_options():
    base=['--year','2025','--bronze_bucket','bronze','--silver_bucket','silver','--runs_table','runs','--database','silver']
    a=options(base+['--engine','glue','--JOB_NAME','historical-glue','--job-bookmark-option','job-bookmark-disable'])
    assert a.year=='2025' and a.engine=='glue' and a.bronze_bucket=='bronze'
    with pytest.raises(SystemExit):options(base+['--unexpected','value'])


def test_legacy_official_zip_member_supported(tmp_path):
    result = prepare_b3(annual(tmp_path, year=1986, member='COTAHIST.A1986'), 1986, tmp_path/'out')
    assert result['scoped_rows'] == 1


def test_audit_reports_bad_ohlc_and_conflicts_without_modifying_sources(tmp_path):
    from src.history.prepare import audit_quotes
    from test_silver import quotation
    row = bytearray(quotation()); row[2:10] = b'20251001'
    bad = bytearray(row); bad[56:69] = b'0000000099999'
    conflict = bytearray(row); conflict[147:152] = b'00013'
    path = tmp_path/'quotes-10.txt'
    original = b'\n'.join([row, row, bad, conflict]) + b'\n'
    path.write_bytes(original)
    report = audit_quotes(tmp_path, 2025)
    assert report['rows'] == 4 and report['exact_duplicates'] == 1
    assert report['unique_valid_keys'] == 1 and not report['ready']
    assert [x['reason'] for x in report['issues']] == ['Invalid OHLC range', 'Conflicting quotation key']
    assert path.read_bytes() == original


def test_quarantine_preserves_source_record_and_reconciles_counts(tmp_path):
    from test_silver import quotation
    valid = bytearray(quotation()); valid[2:10] = b'19861001'
    bad = bytearray(valid); bad[56:69] = b'0000000099999'
    source = annual(tmp_path, year=1986, footer=4)
    with zipfile.ZipFile(source) as archive:
        records = archive.read(archive.namelist()[0]).splitlines()
    with zipfile.ZipFile(source, 'w') as archive:
        archive.writestr('COTAHIST.A1986', b'\r\n'.join([records[0], valid, bad, records[-1]]) + b'\r\n')
    result = prepare_b3(source, 1986, tmp_path/'out', quarantine_invalid=True)
    assert result['source_scoped_rows'] == result['scoped_rows'] + result['quarantined_rows'] == 2
    entry = json.loads((tmp_path/'out/quarantine.jsonl').read_text(encoding='utf-8'))
    assert entry['line'] == 3 and entry['record'].encode('latin-1') == bad
    assert entry['reason'] == 'Invalid OHLC range'


def test_historical_absence_is_explicit_and_strict_default_still_blocks(tmp_path):
    payload = json.dumps([{'data':'04/06/1986','valor':'0.05'}]).encode()
    inputs = {name: payload for name in ['cdi','selic','usd_brl_sell']}
    inputs['cdi'] = json.dumps([{'data':'03/06/1986','valor':'0.05'},{'data':'04/06/1986','valor':'0.05'}]).encode()
    inputs['usd_brl_sell'] = inputs['cdi']
    assert prepare_rates(inputs, 1986, ['1986-06-03','1986-06-04'], tmp_path/'rates.jsonl', historical_coverage=True) == 5
    report = json.loads((tmp_path/'rate-coverage.json').read_text(encoding='utf-8'))
    assert report['unavailable_before_series_start']['selic'] == ['1986-06-03']
    prepare_rates(inputs, 1986, ['1986-06-05'], tmp_path/'rates.jsonl', historical_coverage=True)
    report = json.loads((tmp_path/'rate-coverage.json').read_text(encoding='utf-8'))
    assert report['missing_observations']['cdi'] == ['1986-06-05']
    with pytest.raises(ValueError, match='coverage missing'):
        prepare_rates(inputs, 1986, ['1986-06-05'], tmp_path/'strict.jsonl')
