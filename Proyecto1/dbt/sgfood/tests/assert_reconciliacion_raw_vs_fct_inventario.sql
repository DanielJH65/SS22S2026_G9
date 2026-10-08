-- Reconciliación: filas y unidades del CSV de inventario = filas y unidades del hecho.
with origen as (
    select count(*) as filas, sum(cast(stock_disponible as integer)) as unidades
    from {{ source('archivos', 'csv_inventario_bodega') }}
),

destino as (
    select count(*) as filas, sum(stock_disponible) as unidades
    from {{ ref('fct_inventario_mensual') }}
)

select
    o.filas    as filas_raw,
    d.filas    as filas_fct,
    o.unidades as unidades_raw,
    d.unidades as unidades_fct
from origen as o
cross join destino as d
where o.filas <> d.filas
   or o.unidades <> d.unidades
