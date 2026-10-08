select
    id_marca,
    trim(nombre) as marca,
    _batch_id,
    _loaded_at
from {{ source('oltp', 'oltp_marca') }}
