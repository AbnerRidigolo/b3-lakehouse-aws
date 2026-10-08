"""Streaming validation of one annual COTAHIST archive; no AWS/network calls."""
from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import zipfile
from src.silver.transform import parse_rate, parse_quote

MAX_ZIP = 128 * 1024 * 1024
MAX_EXPANDED = 2 * 1024 * 1024 * 1024


def checked_year(year):
    if not 1986 <= year < date.today().year:
        raise ValueError("Only a complete year from 1986 is allowed")
    return year


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()


def prepare_b3(path, year, output, quarantine_invalid=False):
    checked_year(year)
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    if Path(path).stat().st_size > MAX_ZIP: raise ValueError("Annual ZIP too large")
    handles = {}; scoped = {}; quotes = 0; header = None; trailer = None
    rejected = []; scope_total = 0
    try:
        with zipfile.ZipFile(path) as archive:
            members = archive.infolist()
            if len(members) != 1 or members[0].filename.upper() not in {f'COTAHIST_A{year}.TXT', f'COTAHIST.A{year}'}:
                raise ValueError("Unexpected annual ZIP member")
            if members[0].file_size > MAX_EXPANDED: raise ValueError("Expanded annual file too large")
            with archive.open(members[0]) as source:
                for line_number, physical in enumerate(iter(lambda: source.readline(248), b''), 1):
                    row = physical.rstrip(b'\r\n')
                    if len(row) != 245: raise ValueError("Invalid annual record length")
                    if header is None:
                        if row[:2] != b'00' or row[2:15] != f'COTAHIST.{year}'.encode() or row[15:23].strip() != b'BOVESPA':
                            raise ValueError("Invalid annual header")
                        header = row; continue
                    if trailer is not None: raise ValueError("Record after trailer")
                    if row[:2] == b'99': trailer = row; continue
                    if row[:2] != b'01': raise ValueError("Invalid annual record type")
                    day = datetime.strptime(row[2:10].decode('ascii'), '%Y%m%d').date()
                    if day.year != year: raise ValueError("Quotation outside requested year")
                    quotes += 1
                    if row[10:12] == b'02' and row[24:27] == b'010':
                        scope_total += 1
                        if quarantine_invalid:
                            try:
                                parse_quote(row, day)
                            except ValueError as exc:
                                rejected.append({'line': line_number, 'reason': str(exc),
                                                 'sha256': hashlib.sha256(row).hexdigest(),
                                                 'record': row.decode('latin-1')})
                                continue
                        month = day.strftime('%m')
                        if month not in handles: handles[month] = (output / f'quotes-{month}.txt').open('wb')
                        # Spark text reader uses UTF-8. Workers restore Latin-1 bytes
                        # before parsing official byte positions; no price transformation.
                        handles[month].write(row.decode('latin-1').encode('utf-8') + b'\n')
                        scoped[str(day)] = scoped.get(str(day), 0) + 1
            if trailer is None or trailer[2:23] != header[2:23] or not trailer[31:42].isdigit():
                raise ValueError("Invalid annual trailer")
            footer = int(trailer[31:42])
            if footer not in [quotes, quotes + 2]: raise ValueError("Annual trailer count mismatch")
            if not scoped: raise ValueError("No scoped quotations")
        if quarantine_invalid:
            with (output / 'quarantine.jsonl').open('w', encoding='utf-8', newline='\n') as stream:
                for record in rejected:
                    stream.write(json.dumps(record, ensure_ascii=True) + '\n')
        return {'raw_rows': quotes, 'source_scoped_rows': scope_total,
                'quarantined_rows': len(rejected), 'scoped_rows': sum(scoped.values()), 'days': scoped,
                'trailer_count_mode': 'quotes_only' if footer == quotes else 'all_records'}
    finally:
        for stream in handles.values(): stream.close()


def prepare_rates(payloads, year, trading_days, output, historical_coverage=False):
    checked_year(year)
    if set(payloads) != {'cdi', 'selic', 'usd_brl_sell'}: raise ValueError("Missing BCB series")
    values = {}; coverage = {}; unavailable = {}; gaps = {}
    starts = {'cdi': '1986-03-06', 'selic': '1986-06-04', 'usd_brl_sell': '1984-11-28'}
    for series, payload in payloads.items():
        rows = json.loads(payload)
        if not isinstance(rows, list) or not rows: raise ValueError("Empty annual BCB data")
        coverage[series] = set()
        for row in rows:
            day = datetime.strptime(row['data'], '%d/%m/%Y').date()
            if day.year != year: raise ValueError("BCB date outside requested year")
            parsed = parse_rate(json.dumps([row]).encode(), day, series)
            key = (str(day), series)
            if key in values and values[key] != parsed: raise ValueError("Conflicting BCB duplicate")
            values[key] = parsed; coverage[series].add(str(day))
        missing = set(trading_days) - coverage[series]
        expected = {day for day in missing if historical_coverage and day < starts[series]}
        if missing - expected and not historical_coverage: raise ValueError(f"BCB coverage missing for {series}: {sorted(missing - expected)[:10]}")
        unavailable[series] = sorted(expected)
        gaps[series] = sorted(missing - expected)
    with Path(output).open('w', encoding='utf-8', newline='\n') as stream:
        for key in sorted(values):
            row = values[key]
            stream.write(json.dumps({**row, 'trading_date': str(row['trading_date']), 'value': str(row['value'])}) + '\n')
    if historical_coverage:
        Path(output).with_name('rate-coverage.json').write_text(json.dumps({
            'series_start': starts, 'unavailable_before_series_start': unavailable,
            'missing_observations': gaps,
            'policy': 'No forward fill or invented observations; downstream comparisons require complete coverage'
        }, indent=2) + '\n', encoding='utf-8')
    return len(values)


def audit_quotes(directory, year):
    """Preflight all prepared quotes locally before paying for Spark workers.

    Reports invalid source records and conflicting keys; never repairs or drops
    source data. Exact duplicates are counted separately, as in the Spark MERGE.
    """
    checked_year(year)
    keys = {}
    issues = []
    currencies = {}
    rows = 0
    duplicates = 0
    paths = sorted(Path(directory).glob('quotes-*.txt'))
    if not paths:
        raise ValueError("No prepared quotation files")
    for path in paths:
        with path.open(encoding='utf-8') as stream:
            for line_number, line in enumerate(stream, 1):
                rows += 1
                raw = line.rstrip('\r\n').encode('latin-1')
                try:
                    day = datetime.strptime(raw[2:10].decode('ascii'), '%Y%m%d').date()
                    if day.year != year:
                        raise ValueError("Quotation outside requested year")
                    parsed = parse_quote(raw, day)
                    if parsed is None:
                        raise ValueError("Unexpected out-of-scope prepared record")
                    key = (str(day), parsed['ticker'])
                    fingerprint = hashlib.sha256(raw).hexdigest()
                    if key in keys:
                        if keys[key] != fingerprint:
                            raise ValueError("Conflicting quotation key")
                        duplicates += 1
                    else:
                        keys[key] = fingerprint
                    currency = parsed['currency']
                    currencies[currency] = currencies.get(currency, 0) + 1
                except (ValueError, UnicodeError) as exc:
                    issues.append({'file': path.name, 'line': line_number,
                                   'reason': str(exc), 'sha256': hashlib.sha256(raw).hexdigest()})
    return {'year': year, 'rows': rows, 'unique_valid_keys': len(keys),
            'exact_duplicates': duplicates, 'currencies': currencies,
            'issues': issues, 'ready': not issues}
