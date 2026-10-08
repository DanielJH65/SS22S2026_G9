-- Producto con su categoría y marca (desnormalizado para dim_producto) y margen de lista.
select
    p.id_producto,
    p.sku,
    p.nombre_producto,
    p.id_categoria,
    c.categoria,
    p.id_marca,
    m.marca,
    p.unidad_medida,
    p.costo_base,
    p.precio_lista,
    case
        when p.precio_lista > 0
            then round((p.precio_lista - p.costo_base) / p.precio_lista, 4)
    end as margen_lista_pct,
    p.activo
from {{ ref('stg_oltp__producto') }} as p
left join {{ ref('stg_oltp__categoria') }} as c on c.id_categoria = p.id_categoria
left join {{ ref('stg_oltp__marca') }} as m on m.id_marca = p.id_marca
