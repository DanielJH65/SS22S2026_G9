select
    id_producto,
    upper(trim(sku))         as sku,
    trim(nombre)             as nombre_producto,
    id_categoria,
    id_marca,
    lower(trim(unidad_medida)) as unidad_medida,
    costo_base,
    precio_lista,
    activo,
    _batch_id,
    _loaded_at
from {{ source('oltp', 'oltp_producto') }}
