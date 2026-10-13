-- Length prefixes distinguish null, empty strings and embedded delimiters.
select *,
    concat(
    {% for column in ['ticker', 'isin', 'company_name', 'specification'] %}
        coalesce(concat(cast(length({{ column }}) as varchar), ':', {{ column }}), '-1:')
        {% if not loop.last %}, {% endif %}
    {% endfor %}
    ) as asset_key,
    cast(open_raw as double) / nullif(quotation_factor, 0) as open_unit,
    cast(high_raw as double) / nullif(quotation_factor, 0) as high_unit,
    cast(low_raw as double) / nullif(quotation_factor, 0) as low_unit,
    cast(close_raw as double) / nullif(quotation_factor, 0) as close_unit
from {{ source('silver', 'b3_daily') }}

