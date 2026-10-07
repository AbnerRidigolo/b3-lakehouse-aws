"""Streaming validation of one annual COTAHIST archive; no AWS/network calls."""
from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import zipfile
from src.silver.transform import parse_rate

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


def prepare_b3(path, year, output):
    checked_year(year)
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    if Path(path).stat().st_size > MAX_ZIP: raise ValueError("Annual ZIP too large")
    handles = {}; scoped = {}; quotes = 0; header = None; trailer = None
    try:
        with zipfile.ZipFile(path) as archive:
            members = archive.infolist()
            if len(members) != 1 or members[0].filename.upper() != f'COTAHIST_A{year}.TXT':
                raise ValueError("Unexpected annual ZIP member")
            if members[0].file_size > MAX_EXPANDED: raise ValueError("Expanded annual file too large")
            with archive.open(members[0]) as source:
                for physical in iter(lambda: source.readline(248), b''):
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
        return {'raw_rows': quotes, 'scoped_rows': sum(scoped.values()), 'days': scoped,
                'trailer_count_mode': 'quotes_only' if footer == quotes else 'all_records'}
    finally:
        for stream in handles.values(): stream.close()


def prepare_rates(payloads, year, trading_days, output):
    checked_year(year)
    if set(payloads) != {'cdi', 'selic', 'usd_brl_sell'}: raise ValueError("Missing BCB series")
    values = {}; coverage = {}
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
        if set(trading_days) - coverage[series]: raise ValueError(f"BCB coverage missing for {series}")
    with Path(output).open('w', encoding='utf-8', newline='\n') as stream:
        for key in sorted(values):
            row = values[key]
            stream.write(json.dumps({**row, 'trading_date': str(row['trading_date']), 'value': str(row['value'])}) + '\n')
    return len(values)
