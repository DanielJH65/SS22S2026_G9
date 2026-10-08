-- Una devolución no puede ocurrir antes de la venta que la origina.
select
    d.id_devolucion,
    d.id_venta,
    v.fecha_venta,
    d.fecha_devolucion
from {{ ref('stg_csv__devoluciones') }} as d
join {{ ref('stg_oltp__venta') }} as v on v.id_venta = d.id_venta
where d.fecha_devolucion < v.fecha_venta
