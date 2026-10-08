-- El subtotal de la fuente debe ser cantidad * precio * (1 - descuento),
-- con tolerancia de 1 centavo por redondeo.
select
    id_detalle,
    cantidad,
    precio_unitario,
    descuento_pct,
    monto_neto,
    round(cantidad * precio_unitario * (1 - descuento_pct), 2) as monto_esperado
from {{ ref('stg_oltp__venta_detalle') }}
where abs(monto_neto - round(cantidad * precio_unitario * (1 - descuento_pct), 2)) > 0.01
