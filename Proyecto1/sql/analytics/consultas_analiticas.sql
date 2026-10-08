-- =============================================================================
-- SG-Food · Consultas analíticas sobre el modelo dimensional (schema marts)
-- Responden preguntas de negocio de ventas e inventario. Ejecutar con psql o
-- desde Metabase (usuario bi_reader). Ventas reales = es_venta_valida (COMPLETADA).
-- =============================================================================

-- Q1. ¿Cómo evolucionan las ventas netas mes a mes? (con variación vs mes anterior)
WITH mensual AS (
    SELECT d.anio_mes,
           sum(f.monto_neto)          AS venta_neta,
           sum(f.margen_bruto)        AS margen_bruto,
           count(DISTINCT f.id_venta) AS num_ventas
    FROM marts.fct_ventas f
    JOIN marts.dim_fecha d ON d.sk_fecha = f.sk_fecha
    WHERE f.es_venta_valida
    GROUP BY d.anio_mes
)
SELECT anio_mes,
       venta_neta,
       margen_bruto,
       round(margen_bruto / venta_neta * 100, 2)                               AS margen_pct,
       num_ventas,
       round(venta_neta / num_ventas, 2)                                       AS ticket_promedio,
       round((venta_neta / lag(venta_neta) OVER (ORDER BY anio_mes) - 1) * 100, 2) AS variacion_pct
FROM mensual
ORDER BY anio_mes;

-- Q2. ¿Qué categorías y marcas generan más venta y margen?
SELECT p.categoria,
       p.marca,
       sum(f.monto_neto)                                              AS venta_neta,
       sum(f.margen_bruto)                                            AS margen_bruto,
       round(sum(f.margen_bruto) / sum(f.monto_neto) * 100, 2)        AS margen_pct,
       round(sum(f.monto_neto) / sum(sum(f.monto_neto)) OVER () * 100, 2) AS participacion_pct
FROM marts.fct_ventas f
JOIN marts.dim_producto p ON p.sk_producto = f.sk_producto
WHERE f.es_venta_valida
GROUP BY p.categoria, p.marca
ORDER BY venta_neta DESC
LIMIT 15;

-- Q3. Top 10 productos por ingreso (ranking) y su margen
SELECT rank() OVER (ORDER BY sum(f.monto_neto) DESC) AS ranking,
       p.sku,
       p.nombre_producto,
       p.categoria,
       sum(f.cantidad)                                          AS unidades,
       sum(f.monto_neto)                                        AS venta_neta,
       round(sum(f.margen_bruto) / sum(f.monto_neto) * 100, 2)  AS margen_pct
FROM marts.fct_ventas f
JOIN marts.dim_producto p ON p.sk_producto = f.sk_producto
WHERE f.es_venta_valida
GROUP BY p.sku, p.nombre_producto, p.categoria
ORDER BY ranking
LIMIT 10;

-- Q4. ¿Qué sucursales cumplen mejor sus metas? (acumulado del período)
SELECT nombre_sucursal,
       sum(meta_ventas)                                       AS meta_total,
       sum(venta_neta)                                        AS venta_total,
       round(sum(venta_neta) / sum(meta_ventas) * 100, 2)     AS cumplimiento_pct,
       sum(monto_devuelto)                                    AS devoluciones,
       rank() OVER (ORDER BY sum(venta_neta) / sum(meta_ventas) DESC) AS ranking
FROM marts.mart_cumplimiento_metas
GROUP BY nombre_sucursal
ORDER BY ranking;

-- Q5. Ventas por canal y método de pago, con tasa de anulación
SELECT c.canal,
       c.metodo_pago,
       count(DISTINCT f.id_venta)                                                    AS ventas,
       count(DISTINCT f.id_venta) FILTER (WHERE c.estado_venta = 'ANULADA')          AS anuladas,
       round(count(DISTINCT f.id_venta) FILTER (WHERE c.estado_venta = 'ANULADA')::numeric
             / count(DISTINCT f.id_venta) * 100, 2)                                  AS tasa_anulacion_pct,
       sum(f.monto_neto) FILTER (WHERE f.es_venta_valida)                            AS venta_neta
FROM marts.fct_ventas f
JOIN marts.dim_condicion_venta c ON c.sk_condicion_venta = f.sk_condicion_venta
GROUP BY c.canal, c.metodo_pago
ORDER BY venta_neta DESC;

-- Q6. ¿Las promociones aumentan las ventas? Líneas con y sin promoción vigente por categoría
SELECT p.categoria,
       CASE WHEN pr.id_promocion = -1 THEN 'Sin promoción' ELSE 'Con promoción' END AS tipo,
       count(*)                                    AS lineas,
       round(avg(f.cantidad), 2)                   AS unidades_promedio_linea,
       round(avg(f.descuento_pct) * 100, 2)        AS descuento_promedio_pct,
       sum(f.monto_neto)                           AS venta_neta
FROM marts.fct_ventas f
JOIN marts.dim_producto p   ON p.sk_producto = f.sk_producto
JOIN marts.dim_promocion pr ON pr.sk_promocion = f.sk_promocion
WHERE f.es_venta_valida
GROUP BY p.categoria, tipo
ORDER BY p.categoria, tipo;

-- Q7. Devoluciones: motivos y tasa de devolución por categoría
SELECT p.categoria,
       d.motivo,
       count(*)                AS devoluciones,
       sum(d.cantidad_devuelta) AS unidades,
       sum(d.monto_devuelto)   AS monto_devuelto,
       round(avg(d.dias_desde_venta), 1) AS dias_promedio_desde_venta
FROM marts.fct_devoluciones d
JOIN marts.dim_producto p ON p.sk_producto = d.sk_producto
GROUP BY ROLLUP (p.categoria, d.motivo)
ORDER BY p.categoria NULLS LAST, monto_devuelto DESC;

-- Q8. Inventario en el último corte: estado por sucursal y valor inmovilizado
SELECT nombre_sucursal,
       count(*) FILTER (WHERE estado_stock = 'SIN STOCK')    AS sin_stock,
       count(*) FILTER (WHERE estado_stock = 'BAJO MÍNIMO')  AS bajo_minimo,
       count(*) FILTER (WHERE estado_stock = 'SOBRE STOCK')  AS sobre_stock,
       count(*) FILTER (WHERE vence_en_60_dias)              AS vencen_en_60_dias,
       sum(valor_inventario)                                 AS valor_inventario
FROM marts.mart_alertas_inventario
GROUP BY nombre_sucursal
ORDER BY valor_inventario DESC;

-- Q9. Productos a reabastecer: bajo mínimo o sin stock y con venta reciente
SELECT nombre_sucursal, sku, nombre_producto, stock_disponible, stock_minimo,
       unidades_promedio_mes, estado_stock
FROM marts.mart_alertas_inventario
WHERE estado_stock IN ('SIN STOCK', 'BAJO MÍNIMO')
  AND unidades_promedio_mes > 0
ORDER BY unidades_promedio_mes DESC
LIMIT 15;

-- Q10. Evolución del valor de inventario por categoría (snapshot mensual, semi-aditivo:
--      se suma por categoría dentro de cada mes, nunca a través de meses)
SELECT d.anio_mes,
       p.categoria,
       sum(i.stock_disponible) AS unidades_en_stock,
       sum(i.valor_inventario) AS valor_inventario
FROM marts.fct_inventario_mensual i
JOIN marts.dim_fecha d    ON d.sk_fecha = i.sk_fecha_corte
JOIN marts.dim_producto p ON p.sk_producto = i.sk_producto
GROUP BY d.anio_mes, p.categoria
ORDER BY d.anio_mes, valor_inventario DESC;

-- Q11. Clientes: aporte por tipo de cliente y ticket promedio
SELECT c.tipo_cliente,
       count(DISTINCT c.id_cliente)                           AS clientes,
       count(DISTINCT f.id_venta)                             AS ventas,
       sum(f.monto_neto)                                      AS venta_neta,
       round(sum(f.monto_neto) / count(DISTINCT f.id_venta), 2) AS ticket_promedio
FROM marts.fct_ventas f
JOIN marts.dim_cliente c ON c.sk_cliente = f.sk_cliente
WHERE f.es_venta_valida
GROUP BY c.tipo_cliente
ORDER BY venta_neta DESC;

-- Q12. Compras: proveedor más barato por producto y ahorro frente al costo base
SELECT p.sku,
       p.nombre_producto,
       pv.nombre_proveedor          AS proveedor_mas_barato,
       c.costo_proveedor,
       c.costo_base_producto,
       c.diferencia_vs_costo_base,
       c.plazo_dias
FROM marts.fct_costos_proveedor c
JOIN marts.dim_producto p   ON p.sk_producto = c.sk_producto
JOIN marts.dim_proveedor pv ON pv.sk_proveedor = c.sk_proveedor
WHERE c.es_proveedor_mas_barato
ORDER BY c.diferencia_vs_costo_base
LIMIT 15;

-- Q13. ¿Qué días de la semana se vende más?
SELECT d.dia_semana_iso,
       d.nombre_dia,
       count(DISTINCT f.id_venta) AS ventas,
       sum(f.monto_neto)          AS venta_neta
FROM marts.fct_ventas f
JOIN marts.dim_fecha d ON d.sk_fecha = f.sk_fecha
WHERE f.es_venta_valida
GROUP BY d.dia_semana_iso, d.nombre_dia
ORDER BY d.dia_semana_iso;
