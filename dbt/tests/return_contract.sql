select ticker, trading_date
from {{ ref('mart_daily') }}
where (return_status <> 'unadjusted_price_return' and daily_price_return is not null)
   or (cumulative_cdi_missing <> previous_cumulative_cdi_missing and cdi_interval_return is not null)
   or (cdi_interval_return is null and excess_return_vs_cdi is not null)
   or (daily_price_return is null and cdi_interval_return is not null)
union all
select ticker, month_start
from {{ ref('mart_monthly') }}
where (not price_coverage_complete and monthly_price_return is not null)
   or (not cdi_coverage_complete and (monthly_cdi_return is not null or excess_return_vs_cdi is not null))

