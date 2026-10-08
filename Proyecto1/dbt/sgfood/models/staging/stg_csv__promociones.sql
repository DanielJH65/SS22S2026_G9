select
    cast(id_promocion as integer)              as id_promocion,
    nombre                                     as nombre_promocion,
    cast(fecha_inicio as date)                 as fecha_inicio,
    cast(fecha_fin as date)                    as fecha_fin,
    cast(id_categoria as integer)              as id_categoria,
    cast(porcentaje_descuento as numeric(5,4)) as porcentaje_descuento,
    _row_number,
    _batch_id,
    _loaded_at
from {{ source('archivos', 'csv_promociones') }}
