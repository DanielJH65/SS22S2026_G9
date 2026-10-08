select
    {{ sk(['id_cliente']) }}                   as sk_cliente,
    id_cliente,
    cast(nit as varchar(20))                   as nit,
    cast(nombre_cliente as varchar(150))       as nombre_cliente,
    cast(tipo_cliente as varchar(40))          as tipo_cliente,
    cast(municipio as varchar(100))            as municipio,
    cast(departamento as varchar(100))         as departamento,
    fecha_alta
from {{ ref('stg_oltp__cliente') }}

union all

select {{ sk_desconocido() }}, -1, null, 'Desconocido', 'Desconocido', null, null, null
