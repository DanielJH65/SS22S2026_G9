{{ config(
    indexes=[
        {'columns': ['sk_fecha']},
        {'columns': ['sk_producto']},
        {'columns': ['sk_sucursal']},
        {'columns': ['sk_cliente']},
        {'columns': ['id_venta']},
    ]
) }}

-- Grano: una línea de venta. Las FK que no encuentran su dimensión apuntan al
-- miembro desconocido (-1) en lugar de perder la fila.
select
    l.id_detalle,
    l.id_venta,
    coalesce(df.sk_fecha, -1)                                   as sk_fecha,
    coalesce(dc.sk_cliente, {{ sk_desconocido() }})              as sk_cliente,
    coalesce(dp.sk_producto, {{ sk_desconocido() }})             as sk_producto,
    coalesce(ds.sk_sucursal, {{ sk_desconocido() }})             as sk_sucursal,
    coalesce(dcv.sk_condicion_venta, {{ sk_desconocido() }})     as sk_condicion_venta,
    coalesce(dpr.sk_promocion, {{ sk_desconocido() }})           as sk_promocion,
    l.cantidad,
    cast(l.precio_unitario as numeric(12,2))                     as precio_unitario,
    cast(l.descuento_pct as numeric(5,4))                        as descuento_pct,
    cast(l.monto_bruto as numeric(14,2))                         as monto_bruto,
    cast(l.monto_descuento as numeric(14,2))                     as monto_descuento,
    cast(l.monto_neto as numeric(14,2))                          as monto_neto,
    cast(l.costo_unitario as numeric(12,2))                      as costo_unitario,
    cast(l.costo_total as numeric(14,2))                         as costo_total,
    cast(l.margen_bruto as numeric(14,2))                        as margen_bruto,
    l.es_venta_valida
from {{ ref('int_ventas_lineas') }} as l
left join {{ ref('dim_fecha') }} as df on df.fecha = l.fecha_venta
left join {{ ref('dim_cliente') }} as dc on dc.id_cliente = l.id_cliente
left join {{ ref('dim_producto') }} as dp on dp.id_producto = l.id_producto
left join {{ ref('dim_sucursal') }} as ds on ds.id_sucursal = l.id_sucursal
left join {{ ref('dim_condicion_venta') }} as dcv
  on dcv.canal = l.canal
 and dcv.metodo_pago = l.metodo_pago
 and dcv.estado_venta = l.estado_venta
left join {{ ref('dim_promocion') }} as dpr on dpr.id_promocion = l.id_promocion
