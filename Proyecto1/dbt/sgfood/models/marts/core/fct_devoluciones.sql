{{ config(
    indexes=[
        {'columns': ['sk_fecha']},
        {'columns': ['sk_producto']},
    ]
) }}

-- Grano: una devolución de un producto de una venta.
-- dim_fecha cumple dos roles: fecha de la devolución y fecha de la venta original.
select
    d.id_devolucion,
    d.id_venta,
    coalesce(df.sk_fecha, -1)                            as sk_fecha,
    coalesce(dfv.sk_fecha, -1)                           as sk_fecha_venta,
    coalesce(dp.sk_producto, {{ sk_desconocido() }})     as sk_producto,
    coalesce(dc.sk_cliente, {{ sk_desconocido() }})      as sk_cliente,
    coalesce(ds.sk_sucursal, {{ sk_desconocido() }})     as sk_sucursal,
    cast(d.motivo as varchar(60))                        as motivo,
    d.cantidad_devuelta,
    cast(d.precio_neto_unitario as numeric(12,4))        as precio_neto_unitario,
    cast(d.monto_devuelto as numeric(14,2))              as monto_devuelto,
    d.dias_desde_venta
from {{ ref('int_devoluciones_enriquecidas') }} as d
left join {{ ref('dim_fecha') }} as df on df.fecha = d.fecha_devolucion
left join {{ ref('dim_fecha') }} as dfv on dfv.fecha = d.fecha_venta
left join {{ ref('dim_producto') }} as dp on dp.id_producto = d.id_producto
left join {{ ref('dim_cliente') }} as dc on dc.id_cliente = d.id_cliente
left join {{ ref('dim_sucursal') }} as ds on ds.id_sucursal = d.id_sucursal
