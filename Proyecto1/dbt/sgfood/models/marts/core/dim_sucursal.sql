select
    {{ sk(['id_sucursal']) }}                       as sk_sucursal,
    id_sucursal,
    cast(nombre_sucursal as varchar(100))           as nombre_sucursal,
    cast(ciudad as varchar(100))                    as ciudad,
    cast(departamento as varchar(100))              as departamento
from {{ ref('stg_oltp__sucursal') }}

union all

select {{ sk_desconocido() }}, -1, 'Desconocida', null, null
