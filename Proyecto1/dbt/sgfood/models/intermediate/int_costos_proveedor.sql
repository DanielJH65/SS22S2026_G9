-- Costo de cada proveedor comparado con el costo base del producto y ranking
-- del proveedor más barato por producto.
select
    pp.id_proveedor,
    pp.nombre_proveedor,
    pp.id_producto,
    pp.fecha_vigencia,
    pp.costo_proveedor,
    pp.plazo_dias,
    p.costo_base                         as costo_base_producto,
    pp.costo_proveedor - p.costo_base    as diferencia_vs_costo_base,
    rank() over (
        partition by pp.id_producto
        order by pp.costo_proveedor
    ) = 1                                as es_proveedor_mas_barato
from {{ ref('stg_csv__proveedores_precios') }} as pp
left join {{ ref('stg_oltp__producto') }} as p on p.id_producto = pp.id_producto
