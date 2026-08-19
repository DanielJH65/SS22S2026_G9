-- =========================================================
-- SCRIPT DDL: MODELO MULTIDIMENSIONAL (STAR SCHEMA)
-- Base de Datos: DB_VuelosBI
-- =========================================================

-- 1. Crear y usar la base de datos
CREATE DATABASE DB_VuelosBI;
GO

USE DB_VuelosBI;
GO

-- =========================================================
-- 2. DIMENSIÓN TIEMPO (Dim_Tiempo)
-- =========================================================
CREATE TABLE Dim_Tiempo (
    ID_Tiempo INT PRIMARY KEY IDENTITY(1,1),
    Fecha DATE NOT NULL,
    Anio INT NOT NULL,
    Mes INT NOT NULL,
    Nombre_Mes VARCHAR(20) NOT NULL,
    Dia INT NOT NULL,
    Dia_Semana INT NOT NULL,
    Nombre_Dia_Semana VARCHAR(20) NOT NULL,
    Trimestre INT NOT NULL
);
GO

-- =========================================================
-- 3. DIMENSIÓN AEROLÍNEA (Dim_Aerolinea)
-- =========================================================
CREATE TABLE Dim_Aerolinea (
    ID_Aerolinea INT PRIMARY KEY IDENTITY(1,1),
    Codigo_IATA VARCHAR(10) NOT NULL,
    Nombre_Aerolinea VARCHAR(100) NOT NULL
);
GO

-- =========================================================
-- 4. DIMENSIÓN AEROPUERTO (Dim_Aeropuerto)
-- =========================================================
CREATE TABLE Dim_Aeropuerto (
    ID_Aeropuerto INT PRIMARY KEY IDENTITY(1,1),
    Codigo_IATA VARCHAR(10) NOT NULL,
    -- En un caso real aquí iría el nombre de la ciudad/país del aeropuerto
    Descripcion VARCHAR(100) NOT NULL 
);
GO

-- =========================================================
-- 5. DIMENSIÓN PASAJERO (Dim_Pasajero)
-- =========================================================
CREATE TABLE Dim_Pasajero (
    ID_Pasajero INT PRIMARY KEY IDENTITY(1,1),
    UUID_Pasajero VARCHAR(50) NOT NULL,
    Genero VARCHAR(20) NOT NULL,
    Edad INT,
    Pais_Origen VARCHAR(10) NOT NULL
);
GO

-- =========================================================
-- 6. DIMENSIÓN CLASE / SERVICIO - TIPO 2 (Dim_Clase_SCD2)
-- REQUISITO OBLIGATORIO: Al menos una dimensión Tipo 2
-- =========================================================
CREATE TABLE Dim_Clase_SCD2 (
    ID_Clase_Sk INT PRIMARY KEY IDENTITY(1,1), -- Llave subrogada (Surrogate Key)
    ID_Clase_Natural VARCHAR(50) NOT NULL,     -- Llave natural del negocio
    Descripcion_Clase VARCHAR(50) NOT NULL,
    Precio_Promedio_Base DECIMAL(10,2),        -- Atributo que podría cambiar y justificar el historial
    Fecha_Inicio_Vigencia DATETIME NOT NULL,
    Fecha_Fin_Vigencia DATETIME NULL,
    Es_Actual BIT NOT NULL DEFAULT 1           -- Flag para saber cuál es el registro vigente
);
GO

-- =========================================================
-- 7. TABLA DE HECHOS (Hechos_Vuelos)
-- =========================================================
CREATE TABLE Hechos_Vuelos (
    ID_Hecho INT PRIMARY KEY IDENTITY(1,1),
    
    -- Llaves Foráneas hacia las dimensiones
    ID_Tiempo INT NOT NULL,
    ID_Aerolinea INT NOT NULL,
    ID_Aeropuerto_Origen INT NOT NULL,
    ID_Aeropuerto_Destino INT NOT NULL,
    ID_Pasajero INT NOT NULL,
    ID_Clase_Sk INT NOT NULL, -- Apunta a la llave subrogada de la Dim Tipo 2
    
    -- Métricas y hechos degenerados (atributos del vuelo mismo)
    Numero_Vuelo VARCHAR(20) NOT NULL,
    Estado_Vuelo VARCHAR(20) NOT NULL,
    Duracion_Minutos INT,
    Retraso_Minutos INT,
    Canal_Venta VARCHAR(50),
    Metodo_Pago VARCHAR(50),
    Precio_Original DECIMAL(10,2),
    Moneda_Original VARCHAR(10),
    Precio_USD DECIMAL(10,2),
    Equipaje INT,
    Prioridad INT,
    
    -- Constraints de Integridad Referencial
    CONSTRAINT FK_Hechos_Tiempo FOREIGN KEY (ID_Tiempo) REFERENCES Dim_Tiempo(ID_Tiempo),
    CONSTRAINT FK_Hechos_Aerolinea FOREIGN KEY (ID_Aerolinea) REFERENCES Dim_Aerolinea(ID_Aerolinea),
    CONSTRAINT FK_Hechos_Origen FOREIGN KEY (ID_Aeropuerto_Origen) REFERENCES Dim_Aeropuerto(ID_Aeropuerto),
    CONSTRAINT FK_Hechos_Destino FOREIGN KEY (ID_Aeropuerto_Destino) REFERENCES Dim_Aeropuerto(ID_Aeropuerto),
    CONSTRAINT FK_Hechos_Pasajero FOREIGN KEY (ID_Pasajero) REFERENCES Dim_Pasajero(ID_Pasajero),
    CONSTRAINT FK_Hechos_Clase FOREIGN KEY (ID_Clase_Sk) REFERENCES Dim_Clase_SCD2(ID_Clase_Sk)
);
GO