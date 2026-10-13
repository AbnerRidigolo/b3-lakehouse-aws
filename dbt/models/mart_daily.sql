with previous as (
    select *,
        {% for col in ['trading_date', 'asset_key', 'currency', 'quotation_factor', 'distribution_number', 'close_unit', 'market_ordinal', 'cumulative_cdi_missing', 'cumulative_cdi_log'] %}
        lag({{ col }}) over (partition by ticker order by trading_date) as previous_{{ col }}{% if not loop.last %},{% endif %}
        {% endfor %}
    from {{ ref('fct_daily_quotes') }}
), classified as (
    select *, close_unit / nullif(previous_close_unit, 0) - 1 as raw_price_change,
        case
            when previous_trading_date is null then 'first_observation'
            when currency <> previous_currency then 'currency_change'
            when asset_key <> previous_asset_key then 'asset_attributes_changed'
            when quotation_factor <> previous_quotation_factor
                or distribution_number <> previous_distribution_number then 'possible_corporate_event'
            when abs(close_unit / nullif(previous_close_unit, 0) - 1) >= 0.30 then 'possible_corporate_event'
            when market_ordinal - previous_market_ordinal <> 1
                or date_diff('day', previous_trading_date, trading_date) > 7 then 'quotation_gap'
            else 'unadjusted_price_return'
        end as return_status
    from previous
), returns as (
    select *,
        return_status = 'possible_corporate_event' as possible_corporate_event,
        case when return_status = 'unadjusted_price_return' then raw_price_change end as daily_price_return,
        case when return_status = 'unadjusted_price_return'
            and cumulative_cdi_missing = previous_cumulative_cdi_missing
            then exp(cumulative_cdi_log - previous_cumulative_cdi_log) - 1 end as cdi_interval_return
    from classified
)
select *,
    case when cdi_interval_return is not null then
        (1 + daily_price_return) / (1 + cdi_interval_return) - 1 end as excess_return_vs_cdi,
    case when count(daily_price_return) over w = 21 then
        stddev_samp(daily_price_return) over w * sqrt(252.0) end as annualized_volatility_21_observations,
    case when count(*) over w = 21 and min(currency) over w = max(currency) over w
        and max(market_ordinal) over w - min(market_ordinal) over w = 20
        and date_diff('day', min(trading_date) over w, max(trading_date) over w) <= 45
        then avg(cast(volume as double)) over w end as mean_volume_21_observations
from returns
window w as (partition by ticker order by trading_date rows between 20 preceding and current row)

