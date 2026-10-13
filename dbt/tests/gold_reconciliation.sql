select 'fact_count' as failure
where (select count(*) from {{ ref('fct_daily_quotes') }}) <>
      (select count(*) from {{ source('silver', 'b3_daily') }})
union all
select 'daily_count' as failure
where (select count(*) from {{ ref('mart_daily') }}) <>
      (select count(*) from {{ ref('fct_daily_quotes') }})

