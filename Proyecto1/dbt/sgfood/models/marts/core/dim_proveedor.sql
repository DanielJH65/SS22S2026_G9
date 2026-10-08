-- Los proveedores solo existen en proveedores_precios.csv: se deduplican por id.
select
    {{ sk(['id_proveedor']) }}                 as sk_proveedor,
    id_proveedor,
    cast(max(nombre_proveedor) as varchar(150)) as nombre_proveedor
from {{ ref('stg_csv__proveedores_precios') }}
group by id_proveedor

union all

select {{ sk_desconocido() }}, -1, 'Desconocido'
