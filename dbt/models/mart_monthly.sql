with market as (
    select cast(date_trunc('month', trading_date) as date) as month_start,
        sum(case when is_observed_trading_day then 1 else 0 end) as expected_observations,
        max(trading_date) = last_day_of_month(max(trading_date)) as calendar_month_complete
    from {{ ref('dim_calendar') }} group by 1
), aggregate_returns as (
    select ticker, cast(date_trunc('month', trading_date) as date) as month_start,
        count(*) as observations, count(daily_price_return) as valid_returns,
        count(cdi_interval_return) as valid_cdi_intervals,
        min(currency) as currency, count(distinct currency) as currency_count,
        sum(ln(1 + daily_price_return)) as price_log,
        sum(ln(1 + cdi_interval_return)) as cdi_log,
        sum(case when possible_corporate_event then 1 else 0 end) as flagged_events,
        min(previous_trading_date) as baseline_date
    from {{ ref('mart_daily') }} group by 1, 2
), qualified as (
    select a.*, m.expected_observations, m.calendar_month_complete,
        m.calendar_month_complete and a.observations = m.expected_observations
            and a.valid_returns = a.observations and a.currency_count = 1
            and a.baseline_date < a.month_start as price_coverage_complete
    from aggregate_returns a join market m on a.month_start = m.month_start
)
select ticker, month_start, currency, observations, valid_returns, expected_observations,
    valid_cdi_intervals, flagged_events, calendar_month_complete, price_coverage_complete,
    price_coverage_complete and valid_cdi_intervals = observations as cdi_coverage_complete,
    case when price_coverage_complete then exp(price_log) - 1 end as monthly_price_return,
    case when price_coverage_complete and valid_cdi_intervals = observations then exp(cdi_log) - 1 end as monthly_cdi_return,
    case when price_coverage_complete and valid_cdi_intervals = observations then exp(price_log - cdi_log) - 1 end as excess_return_vs_cdi
from qualified
