-- =============================================================================
-- Validación 4 · REGLAS DE NEGOCIO sobre el modelo analítico
-- severidad error = dato imposible; warn = anomalía real de la fuente a revisar.
-- =============================================================================

-- @check: ventas_montos_consistentes | tipo: negocio | severidad: error
-- monto_neto = cantidad * precio * (1 - descuento) y monto_bruto - descuento = neto
SELECT id_detalle, cantidad, precio_unitario, descuento_pct, monto_neto
FROM marts.fct_ventas
WHERE abs(monto_neto - round(cantidad * precio_unitario * (1 - descuento_pct), 2)) > 0.01
   OR monto_bruto - monto_descuento <> monto_neto;

-- @check: ventas_valores_validos | tipo: negocio | severidad: error
SELECT id_detalle, cantidad, precio_unitario, descuento_pct
FROM marts.fct_ventas
WHERE cantidad <= 0 OR precio_unitario < 0 OR descuento_pct NOT BETWEEN 0 AND 1;

-- @check: devoluciones_no_superan_venta | tipo: negocio | severidad: error
SELECT d.id_devolucion, d.cantidad_devuelta, sum(v.cantidad) AS cantidad_vendida
FROM marts.fct_devoluciones d
JOIN marts.fct_ventas v ON v.id_venta = d.id_venta AND v.sk_producto = d.sk_producto
GROUP BY d.id_devolucion, d.cantidad_devuelta
HAVING d.cantidad_devuelta > sum(v.cantidad);

-- @check: devoluciones_posteriores_a_venta | tipo: negocio | severidad: error
SELECT id_devolucion, dias_desde_venta
FROM marts.fct_devoluciones
WHERE dias_desde_venta < 0;

-- @check: inventario_sin_negativos_ni_vencidos | tipo: negocio | severidad: error
SELECT sk_inventario, stock_disponible, dias_para_vencer
FROM marts.fct_inventario_mensual
WHERE stock_disponible < 0 OR stock_minimo > stock_maximo OR dias_para_vencer < 0;

-- @check: metas_positivas | tipo: negocio | severidad: error
SELECT anio_mes, sk_sucursal, meta_ventas
FROM marts.fct_metas_ventas
WHERE meta_ventas <= 0 OR meta_unidades <= 0;

-- @check: inventario_sobre_stock | tipo: negocio | severidad: warn
-- Anomalía real de la fuente: existencias por encima del máximo definido.
SELECT sk_inventario, stock_disponible, stock_maximo
FROM marts.fct_inventario_mensual
WHERE es_sobre_maximo;

-- @check: ventas_antes_del_alta_cliente | tipo: negocio | severidad: warn
-- Anomalía real de la fuente: el cliente compra antes de su fecha de alta.
SELECT f.id_venta, d.fecha AS fecha_venta, c.fecha_alta
FROM marts.fct_ventas f
JOIN marts.dim_fecha d   ON d.sk_fecha = f.sk_fecha
JOIN marts.dim_cliente c ON c.sk_cliente = f.sk_cliente
WHERE d.fecha < c.fecha_alta
GROUP BY f.id_venta, d.fecha, c.fecha_alta;
