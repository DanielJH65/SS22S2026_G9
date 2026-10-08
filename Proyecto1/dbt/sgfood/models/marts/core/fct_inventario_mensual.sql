{{ config(
    indexes=[
        {'columns': ['sk_producto']},
        {'columns': ['sk_sucursal']},
    ]
) }}

-- Snapshot periódico: foto del inventario al cierre de cada mes.
-- Las cantidades de stock son SEMI-ADITIVAS (no se suman a través del tiempo).
select
    {{ sk(['i.fecha_corte', 'i.id_sucursal', 'i.id_producto']) }} as sk_inventario,
    coalesce(dfc.sk_fecha, -1)                                    as sk_fecha_corte,
    coalesce(ds.sk_sucursal, {{ sk_desconocido() }})              as sk_sucursal,
    coalesce(dp.sk_producto, {{ sk_desconocido() }})              as sk_producto,
    coalesce(dfv.sk_fecha, -1)                                    as sk_fecha_vencimiento,
    cast(i.lote as varchar(20))                                   as lote,
    i.stock_disponible,
    i.stock_minimo,
    i.stock_maximo,
    cast(dp.costo_base as numeric(12,2))                          as costo_unitario,
    cast(i.stock_disponible * dp.costo_base as numeric(14,2))     as valor_inventario,
    i.fecha_vencimiento - i.fecha_corte                           as dias_para_vencer,
    i.stock_disponible = 0                                        as es_sin_stock,
    i.stock_disponible < i.stock_minimo                           as es_bajo_minimo,
    i.stock_disponible > i.stock_maximo                           as es_sobre_maximo
from {{ ref('stg_csv__inventario_bodega') }} as i
left join {{ ref('dim_fecha') }} as dfc on dfc.fecha = i.fecha_corte
left join {{ ref('dim_fecha') }} as dfv on dfv.fecha = i.fecha_vencimiento
left join {{ ref('dim_sucursal') }} as ds on ds.id_sucursal = i.id_sucursal
left join {{ ref('dim_producto') }} as dp on dp.id_producto = i.id_producto
