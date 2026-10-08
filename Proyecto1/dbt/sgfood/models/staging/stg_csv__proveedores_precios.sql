select
    cast(id_proveedor as integer)          as id_proveedor,
    proveedor                              as nombre_proveedor,
    cast(id_producto as integer)           as id_producto,
    cast(costo_proveedor as numeric(12,2)) as costo_proveedor,
    cast(plazo_dias as smallint)           as plazo_dias,
    cast(fecha_vigencia as date)           as fecha_vigencia,
    _row_number,
    _batch_id,
    _loaded_at
from {{ source('archivos', 'csv_proveedores_precios') }}
