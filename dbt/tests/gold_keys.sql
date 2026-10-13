select 'fact' as model, ticker, cast(trading_date as varchar) as key_date
from {{ ref('fct_daily_quotes') }} group by ticker, trading_date having count(*) <> 1
union all
select 'daily', ticker, cast(trading_date as varchar)
from {{ ref('mart_daily') }} group by ticker, trading_date having count(*) <> 1
union all
select 'monthly', ticker, cast(month_start as varchar)
from {{ ref('mart_monthly') }} group by ticker, month_start having count(*) <> 1

