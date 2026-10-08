{{ config(severity='warn') }}

-- Regla de negocio informativa: un cliente no debería comprar antes de su fecha
-- de alta. La fuente la incumple (dato a revisar con el área comercial), por eso
-- se reporta como advertencia sin detener el pipeline.
select
    v.id_venta,
    v.fecha_venta,
    c.id_cliente,
    c.fecha_alta
from {{ ref('stg_oltp__venta') }} as v
join {{ ref('stg_oltp__cliente') }} as c on c.id_cliente = v.id_cliente
where v.fecha_venta < c.fecha_alta
