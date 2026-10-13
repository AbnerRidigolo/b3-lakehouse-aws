-- Generate at most 366 dates per sequence (Trino's array size limit is 10,000).
with bounds as (
    select min(trading_date) as first_day, max(trading_date) as last_day
    from {{ source('silver', 'b3_daily') }}
), years as (
    select first_day, last_day, y
    from bounds cross join unnest(sequence(year(first_day), year(last_day))) as t(y)
), days as (
    select d as trading_date
    from years cross join unnest(sequence(
        cast(concat(cast(y as varchar), '-01-01') as date),
        cast(concat(cast(y as varchar), '-12-31') as date), interval '1' day
    )) as t(d)
    where d between first_day and last_day
), market as (
    select distinct trading_date from {{ source('silver', 'b3_daily') }}
), joined as (
    select d.trading_date, year(d.trading_date) as calendar_year,
        month(d.trading_date) as calendar_month,
        day_of_week(d.trading_date) between 1 and 5 as is_weekday,
        m.trading_date is not null as is_observed_trading_day,
        r.cdi_percent_day,
        case when m.trading_date is not null and r.cdi_percent_day is null then 1 else 0 end as cdi_missing
    from days d left join market m on d.trading_date = m.trading_date
    left join {{ ref('dim_rates') }} r on d.trading_date = r.trading_date
)
select *,
    sum(case when is_observed_trading_day then 1 else 0 end) over (
        order by trading_date rows between unbounded preceding and current row) as market_ordinal,
    sum(cdi_missing) over (
        order by trading_date rows between unbounded preceding and current row) as cumulative_cdi_missing,
    sum(coalesce(ln(1 + cast(cdi_percent_day as double) / 100), 0)) over (
        order by trading_date rows between unbounded preceding and current row) as cumulative_cdi_log
from joined

