select
    id_cliente,
    trim(nit)           as nit,
    trim(nombre)        as nombre_cliente,
    trim(tipo_cliente)  as tipo_cliente,
    trim(municipio)     as municipio,
    trim(departamento)  as departamento,
    fecha_alta,
    _batch_id,
    _loaded_at
from {{ source('oltp', 'oltp_cliente') }}
