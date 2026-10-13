-- Run only after an approved successful gold build, in its bounded workgroup.
select count(*) as quotes from b3_lakehouse_gold.fct_daily_quotes;

select return_status, count(*) as observations
from b3_lakehouse_gold.mart_daily group by return_status;

select ticker, month_start, currency, monthly_price_return, monthly_cdi_return,
       excess_return_vs_cdi, price_coverage_complete, cdi_coverage_complete
from b3_lakehouse_gold.mart_monthly
where ticker = 'PETR4' and month_start between date '2025-01-01' and date '2025-12-01'
order by month_start;

select ticker, trading_date, raw_price_change, return_status
from b3_lakehouse_gold.mart_daily
where possible_corporate_event and trading_date >= date '2025-01-01'
order by trading_date limit 50;
