select
    id_sucursal,
    trim(nombre)        as nombre_sucursal,
    trim(ciudad)        as ciudad,
    trim(departamento)  as departamento,
    _batch_id,
    _loaded_at
from {{ source('oltp', 'oltp_sucursal') }}
