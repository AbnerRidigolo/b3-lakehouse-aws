select trading_date,
    max(case when series = 'cdi' then value end) as cdi_percent_day,
    max(case when series = 'selic' then value end) as selic_percent_day,
    max(case when series = 'usd_brl_sell' then value end) as usd_sell,
    max(case when series = 'usd_brl_sell' then unit end) as usd_unit
from {{ source('silver', 'bcb_daily') }}
group by trading_date

