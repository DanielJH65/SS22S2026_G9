-- =============================================================================
-- SG-Food · Data Warehouse (PostgreSQL)
-- Proyecto 1 · Seminario de Sistemas 2 · USAC 2S2026 · Grupo 9
--
-- Script DDL idempotente. Crea:
--   1. Schemas por capa: raw, staging, intermediate, marts, audit
--   2. Tablas raw (copia fiel de las fuentes + metadatos de carga, SIN restricciones)
--   3. Tablas de auditoría del pipeline
--   4. Modelo dimensional (estrella) en marts: dimensiones, hechos, PK, FK e índices
--
-- Nota sobre marts: dbt reconstruye estas tablas en cada corrida con
-- `contract: enforced` (mismas columnas, tipos, PK y FK). Este script define el
-- diseño físico y permite crear el DW sin dbt; dbt lo reemplaza de forma idéntica.
-- Las capas staging e intermediate son vistas generadas solo por dbt.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. SCHEMAS
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS intermediate;
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA raw          IS 'Datos crudos tal como llegan de las fuentes (OLTP y CSV) + metadatos de carga';
COMMENT ON SCHEMA staging      IS 'dbt: limpieza, tipado y renombrado 1:1 por fuente (vistas)';
COMMENT ON SCHEMA intermediate IS 'dbt: joins y reglas de negocio reutilizables (vistas)';
COMMENT ON SCHEMA marts        IS 'dbt: modelo dimensional (dimensiones y hechos) para consumo analítico';
COMMENT ON SCHEMA audit        IS 'Bitácora de ejecuciones y control de cargas del pipeline';

-- -----------------------------------------------------------------------------
-- 2. CAPA RAW
--    · Sin PK/FK/NOT NULL/CHECK: raw debe aceptar todo lo que envía la fuente
--      (incluso datos erróneos) para que dbt los detecte y documente.
--    · Tablas oltp_*: conservan los tipos de la BD transaccional.
--    · Tablas csv_*: columnas TEXT (schema-on-read); el tipado ocurre en staging.
--    · Metadatos: _batch_id (corrida), _loaded_at, _source (origen exacto).
-- -----------------------------------------------------------------------------

-- 2.1 Fuente transaccional: oltp_sgfood ---------------------------------------
CREATE TABLE IF NOT EXISTS raw.oltp_sucursal (
    id_sucursal   INTEGER,
    nombre        VARCHAR(100),
    ciudad        VARCHAR(100),
    departamento  VARCHAR(100),
    _batch_id     VARCHAR(36),
    _loaded_at    TIMESTAMPTZ DEFAULT now(),
    _source       VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.oltp_categoria (
    id_categoria  INTEGER,
    nombre        VARCHAR(100),
    _batch_id     VARCHAR(36),
    _loaded_at    TIMESTAMPTZ DEFAULT now(),
    _source       VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.oltp_marca (
    id_marca      INTEGER,
    nombre        VARCHAR(100),
    _batch_id     VARCHAR(36),
    _loaded_at    TIMESTAMPTZ DEFAULT now(),
    _source       VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.oltp_producto (
    id_producto   INTEGER,
    sku           VARCHAR(20),
    nombre        VARCHAR(150),
    id_categoria  INTEGER,
    id_marca      INTEGER,
    unidad_medida VARCHAR(30),
    costo_base    NUMERIC(12,2),
    precio_lista  NUMERIC(12,2),
    activo        BOOLEAN,
    _batch_id     VARCHAR(36),
    _loaded_at    TIMESTAMPTZ DEFAULT now(),
    _source       VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.oltp_cliente (
    id_cliente    INTEGER,
    nit           VARCHAR(20),
    nombre        VARCHAR(150),
    tipo_cliente  VARCHAR(40),
    municipio     VARCHAR(100),
    departamento  VARCHAR(100),
    fecha_alta    DATE,
    _batch_id     VARCHAR(36),
    _loaded_at    TIMESTAMPTZ DEFAULT now(),
    _source       VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.oltp_venta (
    id_venta      BIGINT,
    fecha         DATE,
    id_cliente    INTEGER,
    id_sucursal   INTEGER,
    canal         VARCHAR(30),
    metodo_pago   VARCHAR(30),
    estado        VARCHAR(20),
    _batch_id     VARCHAR(36),
    _loaded_at    TIMESTAMPTZ DEFAULT now(),
    _source       VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.oltp_venta_detalle (
    id_detalle      BIGINT,
    id_venta        BIGINT,
    id_producto     INTEGER,
    cantidad        INTEGER,
    precio_unitario NUMERIC(12,2),
    descuento       NUMERIC(5,4),
    subtotal        NUMERIC(14,2),
    _batch_id       VARCHAR(36),
    _loaded_at      TIMESTAMPTZ DEFAULT now(),
    _source         VARCHAR(200)
);

-- 2.2 Archivos CSV --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw.csv_inventario_bodega (
    fecha_corte       TEXT,
    id_sucursal       TEXT,
    id_producto       TEXT,
    stock_disponible  TEXT,
    stock_minimo      TEXT,
    stock_maximo      TEXT,
    lote              TEXT,
    fecha_vencimiento TEXT,
    _row_number       INTEGER,
    _batch_id         VARCHAR(36),
    _loaded_at        TIMESTAMPTZ DEFAULT now(),
    _source           VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.csv_metas_ventas (
    periodo        TEXT,
    id_sucursal    TEXT,
    meta_ventas    TEXT,
    meta_unidades  TEXT,
    _row_number    INTEGER,
    _batch_id      VARCHAR(36),
    _loaded_at     TIMESTAMPTZ DEFAULT now(),
    _source        VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.csv_promociones (
    id_promocion          TEXT,
    nombre                TEXT,
    fecha_inicio          TEXT,
    fecha_fin             TEXT,
    id_categoria          TEXT,
    porcentaje_descuento  TEXT,
    _row_number           INTEGER,
    _batch_id             VARCHAR(36),
    _loaded_at            TIMESTAMPTZ DEFAULT now(),
    _source               VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.csv_proveedores_precios (
    id_proveedor     TEXT,
    proveedor        TEXT,
    id_producto      TEXT,
    costo_proveedor  TEXT,
    plazo_dias       TEXT,
    fecha_vigencia   TEXT,
    _row_number      INTEGER,
    _batch_id        VARCHAR(36),
    _loaded_at       TIMESTAMPTZ DEFAULT now(),
    _source          VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.csv_devoluciones (
    id_devolucion  TEXT,
    fecha          TEXT,
    id_venta       TEXT,
    id_producto    TEXT,
    cantidad       TEXT,
    motivo         TEXT,
    _row_number    INTEGER,
    _batch_id      VARCHAR(36),
    _loaded_at     TIMESTAMPTZ DEFAULT now(),
    _source        VARCHAR(200)
);

-- -----------------------------------------------------------------------------
-- 3. AUDITORÍA DEL PIPELINE
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.etl_load_log (
    id_log          BIGSERIAL PRIMARY KEY,
    batch_id        VARCHAR(36)  NOT NULL,
    dag_run_id      VARCHAR(250),
    source_name     VARCHAR(200) NOT NULL,          -- ej. oltp_sgfood.venta | inventario_bodega.csv
    target_table    VARCHAR(200) NOT NULL,          -- ej. raw.oltp_venta
    load_mode       VARCHAR(20)  NOT NULL,          -- full | incremental | append
    rows_extracted  INTEGER,
    rows_loaded     INTEGER,
    started_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    status          VARCHAR(20)  NOT NULL DEFAULT 'RUNNING',
    error_message   TEXT,
    CONSTRAINT ck_etl_load_log_status CHECK (status IN ('RUNNING','SUCCESS','FAILED')),
    CONSTRAINT ck_etl_load_log_mode   CHECK (load_mode IN ('full','incremental','append'))
);
CREATE INDEX IF NOT EXISTS ix_etl_load_log_batch ON audit.etl_load_log (batch_id);

CREATE TABLE IF NOT EXISTS audit.load_watermark (
    source_name     VARCHAR(200) PRIMARY KEY,
    watermark_col   VARCHAR(100) NOT NULL,
    last_value      TEXT,
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit.validation_result (
    id_result       BIGSERIAL PRIMARY KEY,
    batch_id        VARCHAR(36),
    check_name      VARCHAR(200) NOT NULL,
    check_type      VARCHAR(50)  NOT NULL,          -- conteo | integridad | nulos_unicidad | negocio
    severity        VARCHAR(10)  NOT NULL DEFAULT 'error',
    failing_rows    INTEGER      NOT NULL,
    passed          BOOLEAN      NOT NULL,
    executed_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_validation_severity CHECK (severity IN ('error','warn'))
);
CREATE INDEX IF NOT EXISTS ix_validation_result_batch ON audit.validation_result (batch_id);

-- Resumen de cada corrida completa del pipeline (lo escribe la última tarea del DAG)
CREATE TABLE IF NOT EXISTS audit.pipeline_run (
    batch_id        VARCHAR(36)  PRIMARY KEY,
    dag_run_id      VARCHAR(250),
    status          VARCHAR(20)  NOT NULL,          -- SUCCESS | FAILED
    loads_ok        INTEGER,
    loads_failed    INTEGER,
    checks_passed   INTEGER,
    checks_failed   INTEGER,
    checks_warned   INTEGER,
    detail          TEXT,
    finished_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_pipeline_run_status CHECK (status IN ('SUCCESS','FAILED'))
);

-- -----------------------------------------------------------------------------
-- 4. MARTS · MODELO DIMENSIONAL (ESTRELLA)
--    · Llaves sustitutas sk_* = md5(llave natural) → deterministas e idempotentes
--      (excepto dim_fecha: sk_fecha = YYYYMMDD).
--    · Cada dimensión incluye un "miembro desconocido" (id = -1) para que un hecho
--      con FK huérfana no se pierda ni rompa la integridad referencial.
-- -----------------------------------------------------------------------------

-- 4.1 DIMENSIONES ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS marts.dim_fecha (
    sk_fecha          INTEGER      PRIMARY KEY,     -- YYYYMMDD; -1 = desconocida
    fecha             DATE         UNIQUE,
    anio              SMALLINT,
    trimestre         SMALLINT,
    mes               SMALLINT,
    nombre_mes        VARCHAR(15),
    anio_mes          CHAR(7),                      -- 'YYYY-MM'
    semana_iso        SMALLINT,
    dia_mes           SMALLINT,
    dia_semana_iso    SMALLINT,                     -- 1 = lunes … 7 = domingo
    nombre_dia        VARCHAR(15),
    es_fin_de_semana  BOOLEAN
);

CREATE TABLE IF NOT EXISTS marts.dim_sucursal (
    sk_sucursal      VARCHAR(32)  PRIMARY KEY,
    id_sucursal      INTEGER      NOT NULL UNIQUE,
    nombre_sucursal  VARCHAR(100) NOT NULL,
    ciudad           VARCHAR(100),
    departamento     VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS marts.dim_producto (
    sk_producto       VARCHAR(32)   PRIMARY KEY,
    id_producto       INTEGER       NOT NULL UNIQUE,
    sku               VARCHAR(20),
    nombre_producto   VARCHAR(150)  NOT NULL,
    id_categoria      INTEGER,
    categoria         VARCHAR(100),
    id_marca          INTEGER,
    marca             VARCHAR(100),
    unidad_medida     VARCHAR(30),
    costo_base        NUMERIC(12,2),
    precio_lista      NUMERIC(12,2),
    margen_lista_pct  NUMERIC(7,4),                 -- (precio_lista - costo_base) / precio_lista
    activo            BOOLEAN
);

CREATE TABLE IF NOT EXISTS marts.dim_cliente (
    sk_cliente      VARCHAR(32)  PRIMARY KEY,
    id_cliente      INTEGER      NOT NULL UNIQUE,
    nit             VARCHAR(20),
    nombre_cliente  VARCHAR(150) NOT NULL,
    tipo_cliente    VARCHAR(40),
    municipio       VARCHAR(100),
    departamento    VARCHAR(100),
    fecha_alta      DATE
);

CREATE TABLE IF NOT EXISTS marts.dim_proveedor (
    sk_proveedor      VARCHAR(32)  PRIMARY KEY,
    id_proveedor      INTEGER      NOT NULL UNIQUE,
    nombre_proveedor  VARCHAR(150) NOT NULL
);

CREATE TABLE IF NOT EXISTS marts.dim_promocion (
    sk_promocion          VARCHAR(32)  PRIMARY KEY,
    id_promocion          INTEGER      NOT NULL UNIQUE,   -- -1 = 'Sin promoción'
    nombre_promocion      VARCHAR(150) NOT NULL,
    id_categoria          INTEGER,
    categoria             VARCHAR(100),
    fecha_inicio          DATE,
    fecha_fin             DATE,
    porcentaje_descuento  NUMERIC(5,4),
    duracion_dias         INTEGER
);

-- Dimensión "junk": agrupa atributos de baja cardinalidad de la venta
CREATE TABLE IF NOT EXISTS marts.dim_condicion_venta (
    sk_condicion_venta  VARCHAR(32) PRIMARY KEY,
    canal               VARCHAR(30) NOT NULL,
    metodo_pago         VARCHAR(30) NOT NULL,
    estado_venta        VARCHAR(20) NOT NULL,
    CONSTRAINT uq_condicion_venta UNIQUE (canal, metodo_pago, estado_venta)
);

-- 4.2 HECHOS ---------------------------------------------------------------------

-- Ventas · grano: una línea de detalle de venta (transaccional)
CREATE TABLE IF NOT EXISTS marts.fct_ventas (
    id_detalle          BIGINT        PRIMARY KEY,         -- dimensión degenerada
    id_venta            BIGINT        NOT NULL,            -- dimensión degenerada
    sk_fecha            INTEGER       NOT NULL REFERENCES marts.dim_fecha (sk_fecha),
    sk_cliente          VARCHAR(32)   NOT NULL REFERENCES marts.dim_cliente (sk_cliente),
    sk_producto         VARCHAR(32)   NOT NULL REFERENCES marts.dim_producto (sk_producto),
    sk_sucursal         VARCHAR(32)   NOT NULL REFERENCES marts.dim_sucursal (sk_sucursal),
    sk_condicion_venta  VARCHAR(32)   NOT NULL REFERENCES marts.dim_condicion_venta (sk_condicion_venta),
    sk_promocion        VARCHAR(32)   NOT NULL REFERENCES marts.dim_promocion (sk_promocion),
    cantidad            INTEGER       NOT NULL,
    precio_unitario     NUMERIC(12,2) NOT NULL,
    descuento_pct       NUMERIC(5,4)  NOT NULL,
    monto_bruto         NUMERIC(14,2) NOT NULL,            -- cantidad * precio_unitario
    monto_descuento     NUMERIC(14,2) NOT NULL,            -- monto_bruto - monto_neto
    monto_neto          NUMERIC(14,2) NOT NULL,            -- subtotal de la fuente
    costo_unitario      NUMERIC(12,2),                     -- costo_base del producto
    costo_total         NUMERIC(14,2),
    margen_bruto        NUMERIC(14,2),                     -- monto_neto - costo_total
    es_venta_valida     BOOLEAN       NOT NULL             -- estado = 'COMPLETADA'
);
CREATE INDEX IF NOT EXISTS ix_fct_ventas_fecha    ON marts.fct_ventas (sk_fecha);
CREATE INDEX IF NOT EXISTS ix_fct_ventas_producto ON marts.fct_ventas (sk_producto);
CREATE INDEX IF NOT EXISTS ix_fct_ventas_sucursal ON marts.fct_ventas (sk_sucursal);
CREATE INDEX IF NOT EXISTS ix_fct_ventas_cliente  ON marts.fct_ventas (sk_cliente);
CREATE INDEX IF NOT EXISTS ix_fct_ventas_venta    ON marts.fct_ventas (id_venta);

-- Devoluciones · grano: una devolución de un producto de una venta
CREATE TABLE IF NOT EXISTS marts.fct_devoluciones (
    id_devolucion         INTEGER       PRIMARY KEY,
    id_venta              BIGINT        NOT NULL,
    sk_fecha              INTEGER       NOT NULL REFERENCES marts.dim_fecha (sk_fecha),     -- fecha devolución
    sk_fecha_venta        INTEGER       NOT NULL REFERENCES marts.dim_fecha (sk_fecha),     -- rol: fecha venta
    sk_producto           VARCHAR(32)   NOT NULL REFERENCES marts.dim_producto (sk_producto),
    sk_cliente            VARCHAR(32)   NOT NULL REFERENCES marts.dim_cliente (sk_cliente),
    sk_sucursal           VARCHAR(32)   NOT NULL REFERENCES marts.dim_sucursal (sk_sucursal),
    motivo                VARCHAR(60)   NOT NULL,
    cantidad_devuelta     INTEGER       NOT NULL,
    precio_neto_unitario  NUMERIC(12,4),                    -- subtotal / cantidad de la línea original
    monto_devuelto        NUMERIC(14,2),
    dias_desde_venta      INTEGER
);
CREATE INDEX IF NOT EXISTS ix_fct_devoluciones_fecha    ON marts.fct_devoluciones (sk_fecha);
CREATE INDEX IF NOT EXISTS ix_fct_devoluciones_producto ON marts.fct_devoluciones (sk_producto);

-- Inventario · grano: foto de cierre de mes por sucursal y producto (snapshot periódico)
-- Medidas de stock son SEMI-ADITIVAS: se suman entre sucursales/productos, no entre meses.
CREATE TABLE IF NOT EXISTS marts.fct_inventario_mensual (
    sk_inventario         VARCHAR(32)   PRIMARY KEY,        -- md5(fecha_corte, sucursal, producto)
    sk_fecha_corte        INTEGER       NOT NULL REFERENCES marts.dim_fecha (sk_fecha),
    sk_sucursal           VARCHAR(32)   NOT NULL REFERENCES marts.dim_sucursal (sk_sucursal),
    sk_producto           VARCHAR(32)   NOT NULL REFERENCES marts.dim_producto (sk_producto),
    sk_fecha_vencimiento  INTEGER       NOT NULL REFERENCES marts.dim_fecha (sk_fecha),     -- rol: vencimiento
    lote                  VARCHAR(20),
    stock_disponible      INTEGER       NOT NULL,
    stock_minimo          INTEGER       NOT NULL,
    stock_maximo          INTEGER       NOT NULL,
    costo_unitario        NUMERIC(12,2),
    valor_inventario      NUMERIC(14,2),                    -- stock_disponible * costo_unitario
    dias_para_vencer      INTEGER,
    es_sin_stock          BOOLEAN       NOT NULL,
    es_bajo_minimo        BOOLEAN       NOT NULL,
    es_sobre_maximo       BOOLEAN       NOT NULL,
    CONSTRAINT uq_fct_inventario_grano UNIQUE (sk_fecha_corte, sk_sucursal, sk_producto)
);
CREATE INDEX IF NOT EXISTS ix_fct_inventario_producto ON marts.fct_inventario_mensual (sk_producto);
CREATE INDEX IF NOT EXISTS ix_fct_inventario_sucursal ON marts.fct_inventario_mensual (sk_sucursal);

-- Metas · grano: mes × sucursal (sk_fecha_mes = primer día del mes)
CREATE TABLE IF NOT EXISTS marts.fct_metas_ventas (
    sk_fecha_mes   INTEGER       NOT NULL REFERENCES marts.dim_fecha (sk_fecha),
    sk_sucursal    VARCHAR(32)   NOT NULL REFERENCES marts.dim_sucursal (sk_sucursal),
    anio_mes       CHAR(7)       NOT NULL,
    meta_ventas    NUMERIC(14,2) NOT NULL,
    meta_unidades  INTEGER       NOT NULL,
    CONSTRAINT pk_fct_metas_ventas PRIMARY KEY (sk_fecha_mes, sk_sucursal)
);

-- Costos de proveedor · grano: proveedor × producto × fecha de vigencia
CREATE TABLE IF NOT EXISTS marts.fct_costos_proveedor (
    sk_proveedor              VARCHAR(32)   NOT NULL REFERENCES marts.dim_proveedor (sk_proveedor),
    sk_producto               VARCHAR(32)   NOT NULL REFERENCES marts.dim_producto (sk_producto),
    sk_fecha_vigencia         INTEGER       NOT NULL REFERENCES marts.dim_fecha (sk_fecha),
    costo_proveedor           NUMERIC(12,2) NOT NULL,
    plazo_dias                SMALLINT,
    costo_base_producto       NUMERIC(12,2),
    diferencia_vs_costo_base  NUMERIC(12,2),               -- costo_proveedor - costo_base
    es_proveedor_mas_barato   BOOLEAN       NOT NULL,      -- menor costo para ese producto
    CONSTRAINT pk_fct_costos_proveedor PRIMARY KEY (sk_proveedor, sk_producto, sk_fecha_vigencia)
);
