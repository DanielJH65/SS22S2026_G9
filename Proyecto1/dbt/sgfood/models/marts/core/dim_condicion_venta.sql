-- Dimensión "junk": combina atributos de baja cardinalidad de la venta
-- (canal x método de pago x estado) en una sola dimensión pequeña.
select distinct
    {{ sk(['canal', 'metodo_pago', 'estado_venta']) }} as sk_condicion_venta,
    cast(canal as varchar(30))                         as canal,
    cast(metodo_pago as varchar(30))                   as metodo_pago,
    cast(estado_venta as varchar(20))                  as estado_venta
from {{ ref('stg_oltp__venta') }}

union all

select {{ sk_desconocido() }}, 'Desconocido', 'Desconocido', 'Desconocido'
