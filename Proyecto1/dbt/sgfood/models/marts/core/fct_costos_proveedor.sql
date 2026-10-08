-- Grano: proveedor x producto x fecha de vigencia del precio.
select
    coalesce(dpv.sk_proveedor, {{ sk_desconocido() }})   as sk_proveedor,
    coalesce(dp.sk_producto, {{ sk_desconocido() }})     as sk_producto,
    coalesce(df.sk_fecha, -1)                            as sk_fecha_vigencia,
    cast(c.costo_proveedor as numeric(12,2))             as costo_proveedor,
    c.plazo_dias,
    cast(c.costo_base_producto as numeric(12,2))         as costo_base_producto,
    cast(c.diferencia_vs_costo_base as numeric(12,2))    as diferencia_vs_costo_base,
    c.es_proveedor_mas_barato
from {{ ref('int_costos_proveedor') }} as c
left join {{ ref('dim_proveedor') }} as dpv on dpv.id_proveedor = c.id_proveedor
left join {{ ref('dim_producto') }} as dp on dp.id_producto = c.id_producto
left join {{ ref('dim_fecha') }} as df on df.fecha = c.fecha_vigencia
