select
    id_venta,
    fecha               as fecha_venta,
    id_cliente,
    id_sucursal,
    trim(canal)         as canal,
    trim(metodo_pago)   as metodo_pago,
    upper(trim(estado)) as estado_venta,
    _batch_id,
    _loaded_at
from {{ source('oltp', 'oltp_venta') }}
