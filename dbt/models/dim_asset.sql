select asset_key, ticker, isin, company_name, specification,
    min(trading_date) as first_observed_date,
    max(trading_date) as last_observed_date
from {{ ref('stg_quotes') }}
group by asset_key, ticker, isin, company_name, specification

