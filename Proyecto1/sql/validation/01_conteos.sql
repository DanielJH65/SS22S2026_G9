-- =============================================================================
-- Validación 1 · CONTEOS Y RECONCILIACIÓN raw -> marts
-- Cada consulta devuelve las filas que INCUMPLEN la regla: 0 filas = OK.
-- El DAG ejecuta cada bloque "@check" y guarda el resultado en audit.validation_result.
-- También se pueden ejecutar a mano en psql.
-- (La reconciliación OLTP -> raw se hace en Python: son bases de datos distintas.)
-- =============================================================================

-- @check: raw_tablas_con_datos | tipo: conteo | severidad: error
-- Ninguna tabla raw puede quedar vacía después de la carga.
SELECT tabla, filas FROM (
              SELECT 'raw.oltp_sucursal'           AS tabla, count(*) AS filas FROM raw.oltp_sucursal
    UNION ALL SELECT 'raw.oltp_categoria',          count(*) FROM raw.oltp_categoria
    UNION ALL SELECT 'raw.oltp_marca',              count(*) FROM raw.oltp_marca
    UNION ALL SELECT 'raw.oltp_producto',           count(*) FROM raw.oltp_producto
    UNION ALL SELECT 'raw.oltp_cliente',            count(*) FROM raw.oltp_cliente
    UNION ALL SELECT 'raw.oltp_venta',              count(*) FROM raw.oltp_venta
    UNION ALL SELECT 'raw.oltp_venta_detalle',      count(*) FROM raw.oltp_venta_detalle
    UNION ALL SELECT 'raw.csv_inventario_bodega',   count(*) FROM raw.csv_inventario_bodega
    UNION ALL SELECT 'raw.csv_metas_ventas',        count(*) FROM raw.csv_metas_ventas
    UNION ALL SELECT 'raw.csv_promociones',         count(*) FROM raw.csv_promociones
    UNION ALL SELECT 'raw.csv_proveedores_precios', count(*) FROM raw.csv_proveedores_precios
    UNION ALL SELECT 'raw.csv_devoluciones',        count(*) FROM raw.csv_devoluciones
) t
WHERE filas = 0;

-- @check: reconciliacion_conteos_raw_vs_marts | tipo: conteo | severidad: error
-- Cada hecho/dimensión tiene exactamente las filas de su fuente (+1 miembro desconocido en dimensiones).
SELECT entidad, filas_raw, filas_marts FROM (
              SELECT 'fct_ventas' AS entidad,
                     (SELECT count(*) FROM raw.oltp_venta_detalle)      AS filas_raw,
                     (SELECT count(*) FROM marts.fct_ventas)             AS filas_marts
    UNION ALL SELECT 'fct_inventario_mensual',
                     (SELECT count(*) FROM raw.csv_inventario_bodega),
                     (SELECT count(*) FROM marts.fct_inventario_mensual)
    UNION ALL SELECT 'fct_devoluciones',
                     (SELECT count(*) FROM raw.csv_devoluciones),
                     (SELECT count(*) FROM marts.fct_devoluciones)
    UNION ALL SELECT 'fct_metas_ventas',
                     (SELECT count(*) FROM raw.csv_metas_ventas),
                     (SELECT count(*) FROM marts.fct_metas_ventas)
    UNION ALL SELECT 'fct_costos_proveedor',
                     (SELECT count(*) FROM raw.csv_proveedores_precios),
                     (SELECT count(*) FROM marts.fct_costos_proveedor)
    UNION ALL SELECT 'dim_cliente',
                     (SELECT count(*) + 1 FROM raw.oltp_cliente),
                     (SELECT count(*) FROM marts.dim_cliente)
    UNION ALL SELECT 'dim_producto',
                     (SELECT count(*) + 1 FROM raw.oltp_producto),
                     (SELECT count(*) FROM marts.dim_producto)
    UNION ALL SELECT 'dim_sucursal',
                     (SELECT count(*) + 1 FROM raw.oltp_sucursal),
                     (SELECT count(*) FROM marts.dim_sucursal)
    UNION ALL SELECT 'dim_promocion',
                     (SELECT count(*) + 1 FROM raw.csv_promociones),
                     (SELECT count(*) FROM marts.dim_promocion)
) t
WHERE filas_raw <> filas_marts;

-- @check: reconciliacion_montos_ventas | tipo: conteo | severidad: error
-- El monto total vendido y las unidades no cambian entre raw y el hecho.
SELECT r.monto AS monto_raw, f.monto AS monto_fct, r.unidades AS unidades_raw, f.unidades AS unidades_fct
FROM (SELECT sum(subtotal) AS monto, sum(cantidad) AS unidades FROM raw.oltp_venta_detalle) r,
     (SELECT sum(monto_neto) AS monto, sum(cantidad) AS unidades FROM marts.fct_ventas) f
WHERE r.monto <> f.monto OR r.unidades <> f.unidades;

-- @check: reconciliacion_stock_inventario | tipo: conteo | severidad: error
SELECT r.unidades AS unidades_raw, f.unidades AS unidades_fct
FROM (SELECT sum(stock_disponible::int) AS unidades FROM raw.csv_inventario_bodega) r,
     (SELECT sum(stock_disponible) AS unidades FROM marts.fct_inventario_mensual) f
WHERE r.unidades <> f.unidades;

-- @check: dim_fecha_cubre_hechos | tipo: conteo | severidad: error
-- El calendario cubre todas las fechas de ventas, inventario y vencimientos.
SELECT 'fecha fuera de dim_fecha' AS problema, fecha
FROM (
    SELECT fecha FROM raw.oltp_venta
    UNION SELECT fecha_corte::date FROM raw.csv_inventario_bodega
    UNION SELECT fecha_vencimiento::date FROM raw.csv_inventario_bodega
) f
WHERE NOT EXISTS (SELECT 1 FROM marts.dim_fecha d WHERE d.fecha = f.fecha);
