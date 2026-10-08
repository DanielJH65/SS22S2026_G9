-- Una fila por línea de venta con su encabezado, costo, promoción atribuida y
-- medidas calculadas. Es la base de fct_ventas y de fct_devoluciones.
with detalle as (
    select * from {{ ref('stg_oltp__venta_detalle') }}
),

venta as (
    select * from {{ ref('stg_oltp__venta') }}
),

producto as (
    select id_producto, id_categoria, costo_base
    from {{ ref('int_productos_enriquecidos') }}
),

lineas as (
    select
        d.id_detalle,
        d.id_venta,
        v.fecha_venta,
        v.id_cliente,
        v.id_sucursal,
        v.canal,
        v.metodo_pago,
        v.estado_venta,
        d.id_producto,
        p.id_categoria,
        d.cantidad,
        d.precio_unitario,
        d.descuento_pct,
        d.monto_neto,
        p.costo_base as costo_unitario
    from detalle as d
    left join venta as v on v.id_venta = d.id_venta
    left join producto as p on p.id_producto = d.id_producto
),

-- Regla de atribución: promoción de la categoría del producto vigente en la
-- fecha de la venta. Si hay traslape, gana el mayor descuento (y luego el menor id).
promocion_aplicable as (
    select
        l.id_detalle,
        pr.id_promocion,
        row_number() over (
            partition by l.id_detalle
            order by pr.porcentaje_descuento desc, pr.id_promocion
        ) as prioridad
    from lineas as l
    join {{ ref('stg_csv__promociones') }} as pr
      on pr.id_categoria = l.id_categoria
     and l.fecha_venta between pr.fecha_inicio and pr.fecha_fin
)

select
    l.*,
    pa.id_promocion,
    round(l.cantidad * l.precio_unitario, 2)                     as monto_bruto,
    round(l.cantidad * l.precio_unitario, 2) - l.monto_neto      as monto_descuento,
    round(l.cantidad * l.costo_unitario, 2)                      as costo_total,
    l.monto_neto - round(l.cantidad * l.costo_unitario, 2)       as margen_bruto,
    coalesce(l.estado_venta = 'COMPLETADA', false)               as es_venta_valida
from lineas as l
left join promocion_aplicable as pa
  on pa.id_detalle = l.id_detalle
 and pa.prioridad = 1
