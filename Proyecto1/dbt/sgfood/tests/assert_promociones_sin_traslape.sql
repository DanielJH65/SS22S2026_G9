{{ config(severity='warn') }}

-- Dos promociones de la misma categoría no deberían estar vigentes a la vez.
-- La fuente sí tiene traslapes; int_ventas_lineas los resuelve aplicando el mayor
-- descuento. Se reporta como advertencia.
select
    a.id_promocion as promocion_a,
    b.id_promocion as promocion_b,
    a.id_categoria,
    greatest(a.fecha_inicio, b.fecha_inicio) as traslape_desde,
    least(a.fecha_fin, b.fecha_fin)          as traslape_hasta
from {{ ref('stg_csv__promociones') }} as a
join {{ ref('stg_csv__promociones') }} as b
  on a.id_categoria = b.id_categoria
 and a.id_promocion < b.id_promocion
 and a.fecha_inicio <= b.fecha_fin
 and b.fecha_inicio <= a.fecha_fin
