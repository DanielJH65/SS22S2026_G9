-- Cada devolución con los datos de la venta original (cliente, sucursal, fecha)
-- y el precio neto unitario efectivamente cobrado, para valorizarla.
with vendido as (
    -- Una venta podría repetir producto en varias líneas: se consolida
    select
        id_venta,
        id_producto,
        min(fecha_venta)  as fecha_venta,
        min(id_cliente)   as id_cliente,
        min(id_sucursal)  as id_sucursal,
        sum(cantidad)     as cantidad_vendida,
        sum(monto_neto)   as monto_neto_vendido
    from {{ ref('int_ventas_lineas') }}
    group by id_venta, id_producto
)

select
    d.id_devolucion,
    d.fecha_devolucion,
    d.id_venta,
    d.id_producto,
    d.cantidad_devuelta,
    d.motivo,
    v.fecha_venta,
    v.id_cliente,
    v.id_sucursal,
    v.cantidad_vendida,
    round(v.monto_neto_vendido / nullif(v.cantidad_vendida, 0), 4)                        as precio_neto_unitario,
    round(d.cantidad_devuelta * v.monto_neto_vendido / nullif(v.cantidad_vendida, 0), 2)  as monto_devuelto,
    d.fecha_devolucion - v.fecha_venta                                                    as dias_desde_venta
from {{ ref('stg_csv__devoluciones') }} as d
left join vendido as v
  on v.id_venta = d.id_venta
 and v.id_producto = d.id_producto
