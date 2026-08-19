USE DB_VuelosBI;
GO

-- =========================================================
-- CONSULTA 1: Validación de Integridad (Conteo Total)
-- Objetivo: Verificar que no se perdieron registros en el ETL
-- =========================================================
SELECT 'Total Registros CSV' AS Concepto, 10001 AS Cantidad
UNION ALL
SELECT 'Total Hechos Cargados', COUNT(*) FROM Hechos_Vuelos;

-- =========================================================
-- CONSULTA 2: Top 5 Destinos Más Frecuentes
-- Objetivo: Identificar las rutas más populares (Análisis de volumen)
-- =========================================================
SELECT TOP 5
    a_destino.Codigo_IATA AS Aeropuerto_Destino,
    a_destino.Descripcion,
    COUNT(*) AS Total_Vuelos
FROM Hechos_Vuelos h
JOIN Dim_Aeropuerto a_destino ON h.ID_Aeropuerto_Destino = a_destino.ID_Aeropuerto
GROUP BY a_destino.Codigo_IATA, a_destino.Descripcion
ORDER BY Total_Vuelos DESC;

-- =========================================================
-- CONSULTA 3: Distribución de Pasajeros por Género
-- Objetivo: Conocer la demografía de los clientes (Análisis de segmentación)
-- =========================================================
SELECT 
    p.Genero,
    COUNT(*) AS Cantidad_Pasajeros,
    CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Hechos_Vuelos) AS DECIMAL(5,2)) AS Porcentaje
FROM Hechos_Vuelos h
JOIN Dim_Pasajero p ON h.ID_Pasajero = p.ID_Pasajero
GROUP BY p.Genero
ORDER BY Cantidad_Pasajeros DESC;

-- =========================================================
-- CONSULTA 4: Ingresos Totales (USD) por Aerolínea y Mes (CORREGIDA)
-- Objetivo: Indicador de negocio clave (KPI) para análisis temporal
-- =========================================================
SELECT 
    a.Nombre_Aerolinea,
    t.Nombre_Mes,
    t.Anio,
    t.Mes, -- Agregamos el mes numérico para poder ordenar cronológicamente
    SUM(h.Precio_USD) AS Ingresos_Totales_USD,
    COUNT(*) AS Boletos_Vendidos
FROM Hechos_Vuelos h
JOIN Dim_Aerolinea a ON h.ID_Aerolinea = a.ID_Aerolinea
JOIN Dim_Tiempo t ON h.ID_Tiempo = t.ID_Tiempo
WHERE h.Estado_Vuelo != 'CANCELLED' -- Excluimos cancelados para ingresos reales
GROUP BY a.Nombre_Aerolinea, t.Nombre_Mes, t.Anio, t.Mes
ORDER BY t.Anio, t.Mes, Ingresos_Totales_USD DESC;

-- =========================================================
-- CONSULTA 5: Promedio de Retraso por Aeropuerto de Origen
-- Objetivo: Análisis de calidad de servicio / puntualidad
-- =========================================================
SELECT 
    a_origen.Codigo_IATA AS Aeropuerto_Origen,
    AVG(CAST(h.Retraso_Minutos AS FLOAT)) AS Promedio_Retraso_Min,
    MAX(h.Retraso_Minutos) AS Maximo_Retraso_Min,
    SUM(CASE WHEN h.Retraso_Minutos > 0 THEN 1 ELSE 0 END) AS Vuelos_Retrasados
FROM Hechos_Vuelos h
JOIN Dim_Aeropuerto a_origen ON h.ID_Aeropuerto_Origen = a_origen.ID_Aeropuerto
WHERE h.Estado_Vuelo IN ('DELAYED', 'ON_TIME') -- Solo vuelos que salieron
GROUP BY a_origen.Codigo_IATA
HAVING AVG(CAST(h.Retraso_Minutos AS FLOAT)) > 0
ORDER BY Promedio_Retraso_Min DESC;

-- =========================================================
-- CONSULTA 6: Ventas por Canal y Método de Pago (Cruce multidimensional)
-- Objetivo: Entender el comportamiento de compra
-- =========================================================
SELECT 
    h.Canal_Venta,
    h.Metodo_Pago,
    COUNT(*) AS Transacciones,
    AVG(h.Precio_USD) AS Ticket_Promedio_USD
FROM Hechos_Vuelos h
WHERE h.Estado_Vuelo != 'CANCELLED'
GROUP BY h.Canal_Venta, h.Metodo_Pago
ORDER BY Transacciones DESC;

-- =========================================================
-- CONSULTA 7: Validación de Dimensión Tipo 2 (SCD2)
-- Objetivo: Demostrar que la dimensión histórica está funcionando
-- =========================================================
SELECT 
    ID_Clase_Sk,
    ID_Clase_Natural,
    Descripcion_Clase,
    Fecha_Inicio_Vigencia,
    Fecha_Fin_Vigencia,
    CASE WHEN Es_Actual = 1 THEN 'Vigente' ELSE 'Histórico' END AS Estado_Registro
FROM Dim_Clase_SCD2
ORDER BY ID_Clase_Natural, Fecha_Inicio_Vigencia;