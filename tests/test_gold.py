"""Execute production model SQL on synthetic data; no network/AWS.

SQLGlot translates Trino syntax to DuckDB for the offline behavioral tests.
This does not replace the required Athena/Iceberg deployment pilot.
"""
from datetime import date, timedelta
from pathlib import Path
import unittest

import duckdb
from jinja2 import Environment, StrictUndefined
import sqlglot

ROOT = Path(__file__).resolve().parents[1] / 'dbt'
ORDER = ['staging/stg_quotes', 'dim_asset', 'dim_rates', 'dim_calendar',
         'fct_daily_quotes', 'mart_daily', 'mart_monthly']


def render(path):
    env = Environment(undefined=StrictUndefined)
    sql = env.from_string(path.read_text(encoding='utf-8')).render(
        source=lambda schema, table: table, ref=lambda name: name,
        config=lambda **kwargs: '')
    return sqlglot.transpile(sql, read='trino', write='duckdb', unsupported_level=sqlglot.ErrorLevel.RAISE)[0]


class GoldTests(unittest.TestCase):
    def setUp(self):
        self.db = duckdb.connect(':memory:')
        self.db.execute('''create table b3_daily (
            trading_date date, ticker varchar, company_name varchar, specification varchar,
            currency varchar, isin varchar, quotation_factor integer, distribution_number integer,
            open_raw decimal(13,2), high_raw decimal(13,2), low_raw decimal(13,2), close_raw decimal(13,2),
            trades integer, quantity bigint, volume decimal(18,2))''')
        self.db.execute('create table bcb_daily (trading_date date, series varchar, value decimal(20,10), unit varchar)')
        self.days = [date(2025, 1, 31) + timedelta(days=n) for n in range(32)
                     if (date(2025, 1, 31) + timedelta(days=n)).weekday() < 5]
        for i, day in enumerate(self.days):
            self.quote(day, 'OK', round(100 * 1.01**i, 2))
            self.db.execute("insert into bcb_daily values (?, 'cdi', 0.01, 'percent_per_day')", [day])

    def tearDown(self):
        self.db.close()

    def quote(self, day, ticker, close, currency='BRL', factor=1, isin='ISIN1'):
        self.db.execute('insert into b3_daily values (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, 10, 100, 1000)',
                        [day, ticker, 'Company', 'ON', currency, isin, factor, close, close, close, close])

    def build(self):
        for name in ORDER:
            self.db.execute(f'create table {name.split("/")[-1]} as ' + render(ROOT / 'models' / f'{name}.sql'))

    def check(self, name):
        return self.db.execute(render(ROOT / 'tests' / f'{name}.sql')).fetchall()

    def test_complete_month_and_rolling_metrics(self):
        self.build()
        row = self.db.execute("select monthly_price_return, monthly_cdi_return, cdi_coverage_complete from mart_monthly where ticker='OK' and month_start=date '2025-02-01'").fetchone()
        close = self.db.execute("select close_raw from b3_daily where trading_date=date '2025-02-28'").fetchone()[0]
        self.assertAlmostEqual(row[0], float(close) / 100 - 1)
        self.assertAlmostEqual(row[1], 1.0001**20 - 1)
        self.assertTrue(row[2])
        rolling = self.db.execute("select annualized_volatility_21_observations, mean_volume_21_observations from mart_daily where trading_date=date '2025-03-03'").fetchone()
        self.assertIsNotNone(rolling[0])
        self.assertEqual(rolling[1], 1000)
        for test in ROOT.joinpath('tests').glob('*.sql'):
            with self.subTest(test=test.name):
                self.assertEqual(self.db.execute(render(test)).fetchall(), [])

    def test_missing_cdi_does_not_fill_or_hide_partial_month(self):
        self.db.execute("delete from bcb_daily where trading_date=date '2025-02-10'")
        self.build()
        row = self.db.execute("select daily_price_return, cdi_interval_return, excess_return_vs_cdi from mart_daily where trading_date=date '2025-02-10'").fetchone()
        self.assertIsNotNone(row[0]); self.assertEqual(row[1:], (None, None))
        row = self.db.execute("select monthly_price_return, monthly_cdi_return, cdi_coverage_complete from mart_monthly where month_start=date '2025-02-01'").fetchone()
        self.assertIsNotNone(row[0]); self.assertIsNone(row[1]); self.assertFalse(row[2])
        row = self.db.execute("select monthly_price_return, calendar_month_complete from mart_monthly where month_start=date '2025-03-01'").fetchone()
        self.assertEqual(row, (None, False))

    def test_currency_split_factor_identity_and_quotation_gaps(self):
        a, b, c = self.days[:3]
        for ticker in ['SPLIT', 'FACTOR', 'CURRENCY', 'IDENTITY', 'GAP']:
            self.quote(a, ticker, 100)
        self.quote(b, 'SPLIT', 50)
        self.quote(b, 'FACTOR', 10000, factor=100)
        self.quote(b, 'CURRENCY', 101, currency='CZ$')
        self.quote(b, 'IDENTITY', 101, isin='ISIN2')
        self.quote(c, 'GAP', 101)
        self.build()
        states = dict(self.db.execute("select ticker, return_status from mart_daily where ticker <> 'OK' and previous_trading_date is not null").fetchall())
        self.assertEqual(states, {'SPLIT': 'possible_corporate_event', 'FACTOR': 'possible_corporate_event',
            'CURRENCY': 'currency_change', 'IDENTITY': 'asset_attributes_changed', 'GAP': 'quotation_gap'})
        self.assertEqual(self.db.execute("select count(*) from mart_daily where ticker <> 'OK' and daily_price_return is not null").fetchone()[0], 0)
        self.assertEqual(self.db.execute("select close_unit from fct_daily_quotes where ticker='FACTOR' order by trading_date").fetchall(), [(100.0,), (100.0,)])
        self.assertEqual(self.db.execute("select count(*) from dim_asset where ticker='IDENTITY'").fetchone()[0], 2)

    def test_source_contract_rejects_duplicates_and_bad_ranges(self):
        self.assertEqual(self.check('source_quotes_contract'), [])
        self.db.execute('insert into b3_daily select * from b3_daily limit 1')
        self.assertTrue(self.check('source_quotes_contract'))
        self.db.execute("update b3_daily set low_raw=200, high_raw=10 where trading_date=date '2025-02-03'")
        self.assertEqual(len(self.check('source_quotes_contract')), 2)
        self.db.execute("update bcb_daily set unit='annual_percent' where trading_date=date '2025-02-03'")
        self.assertTrue(self.check('source_rates_contract'))

    def test_historical_calendar_gap_and_original_currency(self):
        self.quote(date(1986, 1, 2), 'OLD', 100, currency='CR$')
        self.quote(date(1986, 1, 3), 'OLD', 101, currency='CR$')
        self.db.execute("insert into bcb_daily values (date '1986-01-02', 'usd_brl_sell', 100, 'current_currency/USD')")
        self.build()
        self.assertGreater(self.db.execute('select count(*) from dim_calendar').fetchone()[0], 10000)
        self.assertEqual(self.db.execute("select currency, daily_price_return, cdi_interval_return from mart_daily where ticker='OLD' and trading_date=date '1986-01-03'").fetchone(), ('CR$', 0.010000000000000009, None))
        self.assertEqual(self.db.execute("select usd_unit from dim_rates where trading_date=date '1986-01-02'").fetchone()[0], 'current_currency/USD')
        self.assertEqual(self.check('source_rates_contract'), [])


if __name__ == '__main__':
    unittest.main()
