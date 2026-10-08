-- Reconciliación de punta a punta: lo que llegó a raw debe ser exactamente lo
-- que hay en el hecho (mismas líneas y mismo monto total, sin pérdidas ni duplicados).
with origen as (
    select count(*) as lineas, sum(subtotal) as monto
    from {{ source('oltp', 'oltp_venta_detalle') }}
),

destino as (
    select count(*) as lineas, sum(monto_neto) as monto
    from {{ ref('fct_ventas') }}
)

select
    o.lineas as lineas_raw,
    d.lineas as lineas_fct,
    o.monto  as monto_raw,
    d.monto  as monto_fct
from origen as o
cross join destino as d
where o.lineas <> d.lineas
   or o.monto <> d.monto
