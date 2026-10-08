-- Producto desnormalizado (categoría y marca incluidas): esquema estrella, no copo de nieve.
select
    {{ sk(['id_producto']) }}                  as sk_producto,
    id_producto,
    cast(sku as varchar(20))                   as sku,
    cast(nombre_producto as varchar(150))      as nombre_producto,
    id_categoria,
    cast(categoria as varchar(100))            as categoria,
    id_marca,
    cast(marca as varchar(100))                as marca,
    cast(unidad_medida as varchar(30))         as unidad_medida,
    cast(costo_base as numeric(12,2))          as costo_base,
    cast(precio_lista as numeric(12,2))        as precio_lista,
    cast(margen_lista_pct as numeric(7,4))     as margen_lista_pct,
    activo
from {{ ref('int_productos_enriquecidos') }}

union all

select
    {{ sk_desconocido() }}, -1, null, 'Desconocido', null, 'Desconocida', null, 'Desconocida',
    null, null, null, null, null
