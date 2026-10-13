-- Unpartitioned: the full history has >100 monthly partitions, above CTAS limit.
-- Source is currently ~84 MB. Revisit partitioning after measured pilot costs.
select q.trading_date, q.ticker, q.asset_key, q.currency,
    q.quotation_factor, q.distribution_number,
    q.open_raw, q.high_raw, q.low_raw, q.close_raw,
    q.open_unit, q.high_unit, q.low_unit, q.close_unit,
    q.trades, q.quantity, q.volume,
    c.market_ordinal, c.cumulative_cdi_missing, c.cumulative_cdi_log
from {{ ref('stg_quotes') }} q
join {{ ref('dim_calendar') }} c on q.trading_date = c.trading_date

