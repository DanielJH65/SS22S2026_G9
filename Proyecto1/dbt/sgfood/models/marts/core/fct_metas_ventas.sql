-- Grano: mes x sucursal. sk_fecha_mes apunta al primer día del mes.
select
    coalesce(df.sk_fecha, -1)                          as sk_fecha_mes,
    coalesce(ds.sk_sucursal, {{ sk_desconocido() }})   as sk_sucursal,
    cast(m.anio_mes as char(7))                        as anio_mes,
    cast(m.meta_ventas as numeric(14,2))               as meta_ventas,
    m.meta_unidades
from {{ ref('stg_csv__metas_ventas') }} as m
left join {{ ref('dim_fecha') }} as df on df.fecha = m.fecha_mes
left join {{ ref('dim_sucursal') }} as ds on ds.id_sucursal = m.id_sucursal
