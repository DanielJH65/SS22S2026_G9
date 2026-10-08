-- Venta real vs meta por sucursal y mes (solo ventas COMPLETADA), neta de devoluciones.
with ventas as (
    select
        f.sk_sucursal,
        d.anio_mes,
        sum(f.monto_neto)          as venta_neta,
        sum(f.cantidad)            as unidades_vendidas,
        count(distinct f.id_venta) as num_ventas,
        sum(f.margen_bruto)        as margen_bruto
    from {{ ref('fct_ventas') }} as f
    join {{ ref('dim_fecha') }} as d on d.sk_fecha = f.sk_fecha
    where f.es_venta_valida
    group by 1, 2
),

devoluciones as (
    select
        f.sk_sucursal,
        d.anio_mes,
        sum(f.monto_devuelto)    as monto_devuelto,
        sum(f.cantidad_devuelta) as unidades_devueltas
    from {{ ref('fct_devoluciones') }} as f
    join {{ ref('dim_fecha') }} as d on d.sk_fecha = f.sk_fecha
    group by 1, 2
)

select
    m.anio_mes,
    s.id_sucursal,
    s.nombre_sucursal,
    m.meta_ventas,
    m.meta_unidades,
    coalesce(v.venta_neta, 0)                                       as venta_neta,
    coalesce(dv.monto_devuelto, 0)                                  as monto_devuelto,
    coalesce(v.venta_neta, 0) - coalesce(dv.monto_devuelto, 0)      as venta_neta_menos_devoluciones,
    coalesce(v.unidades_vendidas, 0)                                as unidades_vendidas,
    coalesce(v.num_ventas, 0)                                       as num_ventas,
    coalesce(v.margen_bruto, 0)                                     as margen_bruto,
    round(coalesce(v.venta_neta, 0) / nullif(m.meta_ventas, 0), 4)            as pct_cumplimiento_ventas,
    round(coalesce(v.unidades_vendidas, 0)::numeric / nullif(m.meta_unidades, 0), 4) as pct_cumplimiento_unidades,
    coalesce(v.venta_neta, 0) >= m.meta_ventas                      as cumplio_meta_ventas
from {{ ref('fct_metas_ventas') }} as m
join {{ ref('dim_sucursal') }} as s on s.sk_sucursal = m.sk_sucursal
left join ventas as v on v.sk_sucursal = m.sk_sucursal and v.anio_mes = m.anio_mes
left join devoluciones as dv on dv.sk_sucursal = m.sk_sucursal and dv.anio_mes = m.anio_mes
