-- No debe haber lotes ya vencidos registrados como inventario disponible
-- (caso de calidad "Vencimiento anterior al corte").
select
    fecha_corte,
    id_sucursal,
    id_producto,
    lote,
    fecha_vencimiento
from {{ ref('stg_csv__inventario_bodega') }}
where fecha_vencimiento < fecha_corte
