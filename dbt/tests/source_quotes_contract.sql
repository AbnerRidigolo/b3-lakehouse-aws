{{ config(tags=['source_contract']) }}
select ticker, trading_date
from {{ source('silver', 'b3_daily') }}
group by ticker, trading_date
having count(*) <> 1 or ticker is null or trading_date is null
    or sum(case when currency is null or quotation_factor is null or quotation_factor <= 0
        or low_raw is null or high_raw is null or open_raw is null or close_raw is null
        or low_raw <= 0 or high_raw < low_raw
        or open_raw not between low_raw and high_raw
        or close_raw not between low_raw and high_raw
        or trades is null or trades < 0 or quantity is null or quantity < 0
        or volume is null or volume < 0 then 1 else 0 end) > 0

