-- =============================================================================
-- Validación 3 · NULOS Y UNICIDAD
-- Cada consulta devuelve las filas que INCUMPLEN la regla: 0 filas = OK.
-- =============================================================================

-- @check: raw_llaves_nulas | tipo: nulos_unicidad | severidad: error
SELECT 'oltp_cliente.id_cliente' AS columna, count(*) AS nulos FROM raw.oltp_cliente WHERE id_cliente IS NULL HAVING count(*) > 0
UNION ALL SELECT 'oltp_producto.id_producto', count(*) FROM raw.oltp_producto WHERE id_producto IS NULL HAVING count(*) > 0
UNION ALL SELECT 'oltp_venta.id_venta', count(*) FROM raw.oltp_venta WHERE id_venta IS NULL HAVING count(*) > 0
UNION ALL SELECT 'oltp_venta_detalle.id_detalle', count(*) FROM raw.oltp_venta_detalle WHERE id_detalle IS NULL HAVING count(*) > 0
UNION ALL SELECT 'csv_devoluciones.id_devolucion', count(*) FROM raw.csv_devoluciones WHERE id_devolucion IS NULL HAVING count(*) > 0;

-- @check: raw_llaves_duplicadas | tipo: nulos_unicidad | severidad: error
SELECT 'oltp_cliente' AS tabla, id_cliente::text AS llave, count(*) AS veces FROM raw.oltp_cliente GROUP BY id_cliente HAVING count(*) > 1
UNION ALL SELECT 'oltp_producto', id_producto::text, count(*) FROM raw.oltp_producto GROUP BY id_producto HAVING count(*) > 1
UNION ALL SELECT 'oltp_venta', id_venta::text, count(*) FROM raw.oltp_venta GROUP BY id_venta HAVING count(*) > 1
UNION ALL SELECT 'oltp_venta_detalle', id_detalle::text, count(*) FROM raw.oltp_venta_detalle GROUP BY id_detalle HAVING count(*) > 1
UNION ALL SELECT 'csv_inventario_bodega', fecha_corte || '/' || id_sucursal || '/' || id_producto, count(*)
          FROM raw.csv_inventario_bodega GROUP BY fecha_corte, id_sucursal, id_producto HAVING count(*) > 1;

-- @check: raw_medidas_nulas | tipo: nulos_unicidad | severidad: error
SELECT 'venta_detalle' AS tabla, id_detalle::text AS llave
FROM raw.oltp_venta_detalle
WHERE cantidad IS NULL OR precio_unitario IS NULL OR subtotal IS NULL
UNION ALL
SELECT 'proveedores_precios', id_proveedor || '/' || id_producto
FROM raw.csv_proveedores_precios WHERE costo_proveedor IS NULL
UNION ALL
SELECT 'inventario_bodega', fecha_corte || '/' || id_sucursal || '/' || id_producto
FROM raw.csv_inventario_bodega WHERE stock_disponible IS NULL;

-- @check: marts_llaves_naturales_unicas | tipo: nulos_unicidad | severidad: error
SELECT 'dim_cliente' AS dimension, id_cliente::text AS llave FROM marts.dim_cliente GROUP BY id_cliente HAVING count(*) > 1
UNION ALL SELECT 'dim_producto', id_producto::text FROM marts.dim_producto GROUP BY id_producto HAVING count(*) > 1
UNION ALL SELECT 'dim_sucursal', id_sucursal::text FROM marts.dim_sucursal GROUP BY id_sucursal HAVING count(*) > 1
UNION ALL SELECT 'dim_fecha', fecha::text FROM marts.dim_fecha WHERE fecha IS NOT NULL GROUP BY fecha HAVING count(*) > 1;

-- @check: marts_un_solo_miembro_desconocido | tipo: nulos_unicidad | severidad: error
SELECT dimension, miembros FROM (
              SELECT 'dim_cliente' AS dimension, count(*) AS miembros FROM marts.dim_cliente WHERE id_cliente = -1
    UNION ALL SELECT 'dim_producto', count(*) FROM marts.dim_producto WHERE id_producto = -1
    UNION ALL SELECT 'dim_sucursal', count(*) FROM marts.dim_sucursal WHERE id_sucursal = -1
    UNION ALL SELECT 'dim_promocion', count(*) FROM marts.dim_promocion WHERE id_promocion = -1
    UNION ALL SELECT 'dim_fecha', count(*) FROM marts.dim_fecha WHERE sk_fecha = -1
) t
WHERE miembros <> 1;
