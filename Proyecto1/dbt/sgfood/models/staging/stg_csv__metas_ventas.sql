select
    periodo                                    as anio_mes,
    to_date(periodo || '-01', 'YYYY-MM-DD')    as fecha_mes,
    cast(id_sucursal as integer)               as id_sucursal,
    cast(meta_ventas as numeric(14,2))         as meta_ventas,
    cast(meta_unidades as integer)             as meta_unidades,
    _row_number,
    _batch_id,
    _loaded_at
from {{ source('archivos', 'csv_metas_ventas') }}
