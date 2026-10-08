-- =============================================================================
-- Validación 2 · INTEGRIDAD REFERENCIAL
-- En raw (sin FK físicas) se valida con LEFT JOIN; en marts además existen FK reales.
-- Cada consulta devuelve las filas huérfanas: 0 filas = OK.
-- =============================================================================

-- @check: raw_venta_sin_cliente | tipo: integridad | severidad: error
SELECT v.id_venta, v.id_cliente
FROM raw.oltp_venta v
LEFT JOIN raw.oltp_cliente c ON c.id_cliente = v.id_cliente
WHERE c.id_cliente IS NULL;

-- @check: raw_venta_sin_sucursal | tipo: integridad | severidad: error
SELECT v.id_venta, v.id_sucursal
FROM raw.oltp_venta v
LEFT JOIN raw.oltp_sucursal s ON s.id_sucursal = v.id_sucursal
WHERE s.id_sucursal IS NULL;

-- @check: raw_detalle_sin_venta_o_producto | tipo: integridad | severidad: error
SELECT d.id_detalle, d.id_venta, d.id_producto
FROM raw.oltp_venta_detalle d
LEFT JOIN raw.oltp_venta v    ON v.id_venta = d.id_venta
LEFT JOIN raw.oltp_producto p ON p.id_producto = d.id_producto
WHERE v.id_venta IS NULL OR p.id_producto IS NULL;

-- @check: raw_inventario_sin_producto_o_sucursal | tipo: integridad | severidad: error
SELECT i.fecha_corte, i.id_sucursal, i.id_producto
FROM raw.csv_inventario_bodega i
LEFT JOIN raw.oltp_producto p ON p.id_producto = i.id_producto::int
LEFT JOIN raw.oltp_sucursal s ON s.id_sucursal = i.id_sucursal::int
WHERE p.id_producto IS NULL OR s.id_sucursal IS NULL;

-- @check: raw_devolucion_sin_linea_vendida | tipo: integridad | severidad: error
-- Cada devolución debe corresponder a un producto que realmente se vendió en esa venta.
SELECT d.id_devolucion, d.id_venta, d.id_producto
FROM raw.csv_devoluciones d
LEFT JOIN raw.oltp_venta_detalle vd
       ON vd.id_venta = d.id_venta::bigint AND vd.id_producto = d.id_producto::int
WHERE vd.id_detalle IS NULL;

-- @check: raw_proveedor_producto_inexistente | tipo: integridad | severidad: error
SELECT pp.id_proveedor, pp.id_producto
FROM raw.csv_proveedores_precios pp
LEFT JOIN raw.oltp_producto p ON p.id_producto = pp.id_producto::int
WHERE p.id_producto IS NULL;

-- @check: marts_fct_ventas_huerfanos | tipo: integridad | severidad: error
-- Redundante con las FK físicas: confirma que siguen vigentes tras la reconstrucción de dbt.
SELECT f.id_detalle
FROM marts.fct_ventas f
LEFT JOIN marts.dim_fecha d     ON d.sk_fecha = f.sk_fecha
LEFT JOIN marts.dim_cliente c   ON c.sk_cliente = f.sk_cliente
LEFT JOIN marts.dim_producto p  ON p.sk_producto = f.sk_producto
LEFT JOIN marts.dim_sucursal s  ON s.sk_sucursal = f.sk_sucursal
WHERE d.sk_fecha IS NULL OR c.sk_cliente IS NULL OR p.sk_producto IS NULL OR s.sk_sucursal IS NULL;

-- @check: marts_hechos_en_miembro_desconocido | tipo: integridad | severidad: warn
-- Filas que llegaron a marts sin su dimensión (apuntan al miembro -1).
SELECT 'fct_ventas' AS hecho, count(*) AS filas
FROM marts.fct_ventas
WHERE sk_cliente = md5('-1') OR sk_producto = md5('-1') OR sk_sucursal = md5('-1') OR sk_fecha = -1
HAVING count(*) > 0
UNION ALL
SELECT 'fct_inventario_mensual', count(*)
FROM marts.fct_inventario_mensual
WHERE sk_producto = md5('-1') OR sk_sucursal = md5('-1') OR sk_fecha_corte = -1
HAVING count(*) > 0;

-- @check: marts_fk_fisicas_presentes | tipo: integridad | severidad: error
-- Las FK del modelo estrella deben existir como restricciones en PostgreSQL (20 en total).
SELECT count(*) AS fk_encontradas
FROM information_schema.table_constraints
WHERE constraint_schema = 'marts' AND constraint_type = 'FOREIGN KEY'
HAVING count(*) < 20;
