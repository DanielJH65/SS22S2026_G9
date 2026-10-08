select
    cast(id_devolucion as integer) as id_devolucion,
    cast(fecha as date)            as fecha_devolucion,
    cast(id_venta as bigint)       as id_venta,
    cast(id_producto as integer)   as id_producto,
    cast(cantidad as integer)      as cantidad_devuelta,
    motivo,
    _row_number,
    _batch_id,
    _loaded_at
from {{ source('archivos', 'csv_devoluciones') }}
