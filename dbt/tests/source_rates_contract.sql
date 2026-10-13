{{ config(tags=['source_contract']) }}
select trading_date, series
from {{ source('silver', 'bcb_daily') }}
group by trading_date, series
having count(*) <> 1 or trading_date is null or series is null
    or sum(case when value is null or value < 0
        or series not in ('cdi', 'selic', 'usd_brl_sell')
        or unit is null
        or (series in ('cdi', 'selic') and unit <> 'percent_per_day')
        or (series = 'usd_brl_sell' and unit <> case when trading_date < date '1994-07-01'
            then 'current_currency/USD' else 'BRL/USD' end)
        then 1 else 0 end) > 0

