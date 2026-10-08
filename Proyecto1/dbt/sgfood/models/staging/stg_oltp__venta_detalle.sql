select
    id_detalle,
    id_venta,
    id_producto,
    cantidad,
    precio_unitario,
    descuento  as descuento_pct,
    subtotal   as monto_neto,
    _batch_id,
    _loaded_at
from {{ source('oltp', 'oltp_venta_detalle') }}
