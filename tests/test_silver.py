from datetime import date
from decimal import Decimal
import pytest
from src.silver.transform import parse_quote, parse_rate, safe_identifier

DAY = date(2026, 10, 1)


def quotation():
    row = bytearray(b" " * 245)
    values = [(1, 2, "01"), (3, 10, "20261001"), (11, 12, "02"),
              (13, 24, "TEST3       "), (25, 27, "010"), (28, 39, "EMPRESA TEST"),
              (40, 49, "ON        "), (53, 56, "R$  "), (57, 69, "0000000012345"),
              (70, 82, "0000000013000"), (83, 95, "0000000012000"),
              (109, 121, "0000000012500"), (148, 152, "00012"),
              (153, 170, "000000000000001234"), (171, 188, "000000000000123456"),
              (211, 217, "0001000"), (231, 242, "BRTESTACNOR0"), (243, 245, "001")]
    for a, b, value in values:
        assert len(value) == b - a + 1
        row[a - 1:b] = value.encode()
    return bytes(row)


def test_layout_precision_and_factor_not_silently_discarded():
    r = parse_quote(quotation(), DAY)
    assert r['open_raw'] == Decimal('123.45') and r['close_raw'] == Decimal('125.00')
    assert r['volume'] == Decimal('1234.56') and r['quantity'] == 1234 and r['trades'] == 12
    assert r['quotation_factor'] == 1000 and r['isin'] == 'BRTESTACNOR0'
    assert r['currency'] == 'R$' and r['ticker'] == 'TEST3'


@pytest.mark.parametrize('a,b,value', [(211,217,b'0000000'), (57,69,b'0000000099999'), (148,152,b'00x12')])
def test_invalid_factor_range_or_integer_blocks_load(a,b,value):
    row = bytearray(quotation()); row[a-1:b] = value
    with pytest.raises(ValueError): parse_quote(bytes(row), DAY)


def test_scope_and_wrong_date():
    row = bytearray(quotation()); row[10:12] = b'12'
    assert parse_quote(bytes(row), DAY) is None
    with pytest.raises(ValueError, match='date'): parse_quote(quotation(), date(2026,9,30))


def test_bcb_units_are_daily_percent_and_exchange_rate():
    raw = b'[{"data":"01/10/2026","valor":"0.055131"}]'
    assert parse_rate(raw, DAY, 'cdi')['unit'] == 'percent_per_day'
    assert parse_rate(raw, DAY, 'selic')['value'] == Decimal('0.055131')
    assert parse_rate(raw, DAY, 'usd_brl_sell')['unit'] == 'BRL/USD'
    with pytest.raises(ValueError): parse_rate(raw, DAY, 'unknown')


@pytest.mark.parametrize('value', ['NaN', '-1', '10000000000', '0.12345678901'])
def test_rate_cannot_overflow_or_lose_precision(value):
    raw = ('[{"data":"01/10/2026","valor":"'+value+'"}]').encode()
    with pytest.raises(ValueError): parse_rate(raw, DAY, 'cdi')


def test_catalog_names_cannot_inject_sql():
    assert safe_identifier('b3_lakehouse_silver') == 'b3_lakehouse_silver'
    with pytest.raises(ValueError): safe_identifier('silver; DROP TABLE x')


def test_historical_exchange_rate_is_not_labelled_as_reais():
    raw = b'[{"data":"01/06/1994","valor":"1000"}]'
    result = parse_rate(raw, date(1994, 6, 1), 'usd_brl_sell')
    assert result['unit'] == 'current_currency/USD'
    assert result['value'] == Decimal('1000')
    raw = b'[{"data":"01/07/1994","valor":"1"}]'
    assert parse_rate(raw, date(1994, 7, 1), 'usd_brl_sell')['unit'] == 'BRL/USD'
