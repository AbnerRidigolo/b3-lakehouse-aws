"""Pure COTAHIST transformations; positions follow B3 layout revision 02 (2020).

Prices are unadjusted and retain their quotation factor and original currency.
No file, AWS, network or Spark access occurs in these functions.
"""
from datetime import date, datetime
from decimal import Decimal
import json


def number(row, start, end, scale=0):
    value = row[start - 1:end]
    if not value.isdigit():
        raise ValueError(f"Invalid numeric field at positions {start}-{end}")
    return Decimal(int(value)).scaleb(-scale) if scale else int(value)


def parse_quote(row, target):
    if len(row) != 245 or row[:2] != b"01":
        raise ValueError("Invalid quotation record")
    trading_date = datetime.strptime(row[2:10].decode("ascii"), "%Y%m%d").date()
    if trading_date != target:
        raise ValueError("Wrong quotation date")
    if row[10:12] != b"02" or row[24:27] != b"010":
        return None
    text = lambda a, b: row[a - 1:b].decode("latin-1").strip()
    prices = [number(row, a, b, 2) for a, b in [(57, 69), (70, 82), (83, 95), (109, 121)]]
    opening, high, low, close = prices
    if low <= 0 or not low <= opening <= high or not low <= close <= high:
        raise ValueError("Invalid OHLC range")
    factor = number(row, 211, 217)
    if factor <= 0 or not text(13, 24) or not text(53, 56):
        raise ValueError("Missing ticker, currency or quotation factor")
    return {
        "trading_date": trading_date, "ticker": text(13, 24),
        "company_name": text(28, 39), "specification": text(40, 49),
        "currency": text(53, 56), "isin": text(231, 242) or None,
        "quotation_factor": factor, "distribution_number": number(row, 243, 245),
        "open_raw": opening, "high_raw": high, "low_raw": low, "close_raw": close,
        "trades": number(row, 148, 152), "quantity": number(row, 153, 170),
        "volume": number(row, 171, 188, 2),
    }


def parse_rate(payload, target, series):
    if series not in {"cdi", "selic", "usd_brl_sell"}:
        raise ValueError("Unknown BCB series")
    rows = json.loads(payload)
    if not isinstance(rows, list) or len(rows) != 1:
        raise ValueError("Expected one observation")
    row = rows[0]
    if datetime.strptime(row["data"], "%d/%m/%Y").date() != target:
        raise ValueError("Wrong rate date")
    value = Decimal(row["valor"])
    if not value.is_finite() or value < 0:
        raise ValueError("Invalid rate")
    # SGS 11/12 are percent per day, not annual rates. Store original units.
    if value != value.quantize(Decimal("0.0000000001")) or value >= Decimal("10000000000"):
        raise ValueError("Rate exceeds DECIMAL(20,10)")
    return {"trading_date": target, "series": series, "value": value,
            "unit": "BRL/USD" if series == "usd_brl_sell" else "percent_per_day"}


def safe_identifier(value):
    import re
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,127}", value):
        raise ValueError("Unsafe catalog identifier")
    return value
