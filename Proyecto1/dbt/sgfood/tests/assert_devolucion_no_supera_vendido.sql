-- No se puede devolver más unidades de las que se vendieron en esa venta
-- (caso de calidad "Devolución superior a venta"), ni devolver algo que no se vendió.
-- Valida sobre staging para ejecutarse aunque falle otra prueba de entrada.
with vendido as (
    select id_venta, id_producto, sum(cantidad) as cantidad_vendida
    from {{ ref('stg_oltp__venta_detalle') }}
    group by id_venta, id_producto
)

select
    d.id_devolucion,
    d.id_venta,
    d.id_producto,
    d.cantidad_devuelta,
    v.cantidad_vendida
from {{ ref('stg_csv__devoluciones') }} as d
left join vendido as v
  on v.id_venta = d.id_venta
 and v.id_producto = d.id_producto
where v.cantidad_vendida is null
   or d.cantidad_devuelta > v.cantidad_vendida
