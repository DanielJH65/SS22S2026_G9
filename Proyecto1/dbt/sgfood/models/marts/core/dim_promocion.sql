select
    {{ sk(['pr.id_promocion']) }}               as sk_promocion,
    pr.id_promocion,
    cast(pr.nombre_promocion as varchar(150))   as nombre_promocion,
    pr.id_categoria,
    cast(c.categoria as varchar(100))           as categoria,
    pr.fecha_inicio,
    pr.fecha_fin,
    cast(pr.porcentaje_descuento as numeric(5,4)) as porcentaje_descuento,
    pr.fecha_fin - pr.fecha_inicio + 1          as duracion_dias
from {{ ref('stg_csv__promociones') }} as pr
left join {{ ref('stg_oltp__categoria') }} as c on c.id_categoria = pr.id_categoria

union all

-- Ventas sin promoción vigente apuntan a este miembro
select {{ sk_desconocido() }}, -1, 'Sin promoción', null, null, null, null, 0, null
