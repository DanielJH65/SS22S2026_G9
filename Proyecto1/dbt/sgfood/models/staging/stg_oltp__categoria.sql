select
    id_categoria,
    trim(nombre) as categoria,
    _batch_id,
    _loaded_at
from {{ source('oltp', 'oltp_categoria') }}
