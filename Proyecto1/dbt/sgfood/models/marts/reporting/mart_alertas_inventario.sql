-- Estado del inventario en el ÚLTIMO corte disponible, con rotación reciente
-- (promedio de unidades vendidas en los 3 meses previos al corte) y cobertura.
with ultimo_corte as (
    select max(d.fecha) as fecha_corte
    from {{ ref('fct_inventario_mensual') }} as i
    join {{ ref('dim_fecha') }} as d on d.sk_fecha = i.sk_fecha_corte
),

inventario as (
    select i.*, d.fecha as fecha_corte
    from {{ ref('fct_inventario_mensual') }} as i
    join {{ ref('dim_fecha') }} as d on d.sk_fecha = i.sk_fecha_corte
    join ultimo_corte as u on u.fecha_corte = d.fecha
),

venta_reciente as (
    select
        f.sk_sucursal,
        f.sk_producto,
        sum(f.cantidad) / 3.0 as unidades_promedio_mes
    from {{ ref('fct_ventas') }} as f
    join {{ ref('dim_fecha') }} as d on d.sk_fecha = f.sk_fecha
    cross join ultimo_corte as u
    where f.es_venta_valida
      and d.fecha > u.fecha_corte - interval '3 months'
      and d.fecha <= u.fecha_corte
    group by 1, 2
)

select
    i.fecha_corte,
    s.nombre_sucursal,
    p.sku,
    p.nombre_producto,
    p.categoria,
    i.stock_disponible,
    i.stock_minimo,
    i.stock_maximo,
    i.valor_inventario,
    i.dias_para_vencer,
    round(coalesce(v.unidades_promedio_mes, 0), 2)                         as unidades_promedio_mes,
    round(i.stock_disponible / nullif(v.unidades_promedio_mes, 0), 2)      as meses_cobertura,
    case
        when i.es_sin_stock   then 'SIN STOCK'
        when i.es_bajo_minimo then 'BAJO MÍNIMO'
        when i.es_sobre_maximo then 'SOBRE STOCK'
        else 'OK'
    end                                                                    as estado_stock,
    i.dias_para_vencer <= 60                                               as vence_en_60_dias
from inventario as i
join {{ ref('dim_sucursal') }} as s on s.sk_sucursal = i.sk_sucursal
join {{ ref('dim_producto') }} as p on p.sk_producto = i.sk_producto
left join venta_reciente as v
  on v.sk_sucursal = i.sk_sucursal
 and v.sk_producto = i.sk_producto
