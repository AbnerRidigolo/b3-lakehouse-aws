{{ config(tags=['source_contract']) }}
select 'empty_quotes' as failure
where not exists (select 1 from {{ source('silver', 'b3_daily') }})
union all
select 'empty_rates' as failure
where not exists (select 1 from {{ source('silver', 'bcb_daily') }})

