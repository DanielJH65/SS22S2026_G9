import os
import pandas as pd
import pyodbc
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

SERVER = os.getenv('DB_SERVER')
DATABASE = os.getenv('DB_NAME')
USERNAME = os.getenv('DB_USER')
PASSWORD = os.getenv('DB_PASSWORD')
DRIVER = os.getenv('DB_DRIVER')

if not all([SERVER, DATABASE, USERNAME, PASSWORD, DRIVER]):
    raise ValueError("Faltan variables de entorno en el archivo .env")

conn_str = (
    f'DRIVER={DRIVER};'
    f'SERVER={SERVER};'
    f'DATABASE={DATABASE};'
    f'UID={USERNAME};'
    f'PWD={PASSWORD};'
    f'TrustServerCertificate=yes;'
)

conn = pyodbc.connect(conn_str)
cursor = conn.cursor()

df = pd.read_csv('dataset_vuelos_crudo.csv', header=None)

column_names = [
    'id_vuelo', 'cod_aerolinea', 'nom_aerolinea', 'num_vuelo', 'origen', 'destino',
    'salida', 'llegada', 'duracion', 'estado', 'retraso', 'avion', 'clase', 'asiento',
    'uuid_pasajero', 'genero', 'edad', 'pais', 'fecha_compra', 'canal', 'metodo_pago',
    'precio_orig', 'moneda', 'precio_usd', 'equipaje', 'prioridad'
]
df.columns = column_names

df['cod_aerolinea'] = df['cod_aerolinea'].str[:50]
df['nom_aerolinea'] = df['nom_aerolinea'].str[:100]
df['origen'] = df['origen'].str[:50]
df['destino'] = df['destino'].str[:50]
df['num_vuelo'] = df['num_vuelo'].str[:50]
df['estado'] = df['estado'].str[:50]
df['clase'] = df['clase'].str[:50]
df['canal'] = df['canal'].str[:50]
df['metodo_pago'] = df['metodo_pago'].str[:50]
df['moneda'] = df['moneda'].str[:20]
df['pais'] = df['pais'].str[:50]

def estandarizar_genero(g):
    g = str(g).strip().lower()
    if g in ['m', 'masculino']: return 'Masculino'
    if g in ['f', 'femenino']: return 'Femenino'
    if g in ['x', 'nobinario', 'no binario']: return 'No Binario'
    return 'No Especificado'

df['genero'] = df['genero'].apply(estandarizar_genero)

df['precio_orig'] = df['precio_orig'].astype(str).str.replace(',', '.', regex=False)
df['precio_orig'] = pd.to_numeric(df['precio_orig'], errors='coerce')
df['precio_usd'] = pd.to_numeric(df['precio_usd'], errors='coerce')

def parsear_fecha(fecha_str):
    if pd.isna(fecha_str) or str(fecha_str).strip() == '':
        return None
    fecha_str = str(fecha_str).strip()
    formatos = [
        '%d/%m/%Y %H:%M',
        '%m-%d-%Y %I:%M %p',
        '%d-%m-%Y %H:%M',
        '%Y-%m-%d %H:%M'
    ]
    for fmt in formatos:
        try:
            return datetime.strptime(fecha_str, fmt)
        except ValueError:
            continue
    return None

df['salida_dt'] = df['salida'].apply(parsear_fecha)
df['llegada_dt'] = df['llegada'].apply(parsear_fecha)
df['compra_dt'] = df['fecha_compra'].apply(parsear_fecha)

df['duracion'] = pd.to_numeric(df['duracion'], errors='coerce').fillna(0).astype(int)
df['retraso'] = pd.to_numeric(df['retraso'], errors='coerce').fillna(0).astype(int)
df['edad'] = pd.to_numeric(df['edad'], errors='coerce').fillna(0).astype(int)
df['equipaje'] = pd.to_numeric(df['equipaje'], errors='coerce').fillna(0).astype(int)
df['prioridad'] = pd.to_numeric(df['prioridad'], errors='coerce').fillna(0).astype(int)

df['pais'] = df['pais'].replace('', 'SIN_DATO').fillna('SIN_DATO')
df['canal'] = df['canal'].replace('', 'SIN_DATO').fillna('SIN_DATO')
df['metodo_pago'] = df['metodo_pago'].replace('', 'SIN_DATO').fillna('SIN_DATO')

todas_fechas = pd.concat([df['salida_dt'], df['compra_dt']]).dropna().dt.normalize().unique()
for fecha in todas_fechas:
    fecha_py = pd.Timestamp(fecha).to_pydatetime()
    
    cursor.execute("""
        IF NOT EXISTS (SELECT 1 FROM Dim_Tiempo WHERE Fecha = ?)
        INSERT INTO Dim_Tiempo (Fecha, Anio, Mes, Nombre_Mes, Dia, Dia_Semana, Nombre_Dia_Semana, Trimestre)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, 
    (
        fecha_py.date(), 
        fecha_py.date(), 
        fecha_py.year, 
        fecha_py.month, 
        fecha_py.strftime('%B'), 
        fecha_py.day, 
        fecha_py.weekday()+1, 
        fecha_py.strftime('%A'), 
        (fecha_py.month-1)//3 + 1
    ))
conn.commit()

aerolineas = df[['cod_aerolinea', 'nom_aerolinea']].drop_duplicates()
for _, row in aerolineas.iterrows():
    cursor.execute("""
        IF NOT EXISTS (SELECT 1 FROM Dim_Aerolinea WHERE Codigo_IATA = ?)
        INSERT INTO Dim_Aerolinea (Codigo_IATA, Nombre_Aerolinea) VALUES (?, ?)
    """, row['cod_aerolinea'], row['cod_aerolinea'], row['nom_aerolinea'])
conn.commit()

aeropuertos = pd.concat([df['origen'], df['destino']]).unique()
for aero in aeropuertos:
    cursor.execute("""
        IF NOT EXISTS (SELECT 1 FROM Dim_Aeropuerto WHERE Codigo_IATA = ?)
        INSERT INTO Dim_Aeropuerto (Codigo_IATA, Descripcion) VALUES (?, ?)
    """, aero, aero, f"Aeropuerto {aero}")
conn.commit()

pasajeros = df[['uuid_pasajero', 'genero', 'edad', 'pais']].drop_duplicates(subset=['uuid_pasajero'])
for _, row in pasajeros.iterrows():
    cursor.execute("""
        IF NOT EXISTS (SELECT 1 FROM Dim_Pasajero WHERE UUID_Pasajero = ?)
        INSERT INTO Dim_Pasajero (UUID_Pasajero, Genero, Edad, Pais_Origen) VALUES (?, ?, ?, ?)
    """, row['uuid_pasajero'], row['uuid_pasajero'], row['genero'], int(row['edad']), row['pais'])
conn.commit()

clases = df['clase'].unique()
fecha_vigencia = datetime.now()
for clase in clases:
    cursor.execute("SELECT 1 FROM Dim_Clase_SCD2 WHERE ID_Clase_Natural = ? AND Es_Actual = 1", clase)
    if not cursor.fetchone():
        cursor.execute("""
            INSERT INTO Dim_Clase_SCD2 (ID_Clase_Natural, Descripcion_Clase, Precio_Promedio_Base, Fecha_Inicio_Vigencia, Es_Actual)
            VALUES (?, ?, ?, ?, 1)
        """, clase, f"Clase {clase.title()}", 0.0, fecha_vigencia)
conn.commit()

cursor.execute("SELECT ID_Tiempo, Fecha FROM Dim_Tiempo")
dim_tiempo_lookup = {row[1]: row[0] for row in cursor.fetchall()}

cursor.execute("SELECT ID_Aerolinea, Codigo_IATA FROM Dim_Aerolinea")
dim_aero_lookup = {row[1]: row[0] for row in cursor.fetchall()}

cursor.execute("SELECT ID_Aeropuerto, Codigo_IATA FROM Dim_Aeropuerto")
dim_aeropuerto_lookup = {row[1]: row[0] for row in cursor.fetchall()}

cursor.execute("SELECT ID_Pasajero, UUID_Pasajero FROM Dim_Pasajero")
dim_pasajero_lookup = {row[1]: row[0] for row in cursor.fetchall()}

cursor.execute("SELECT ID_Clase_Sk, ID_Clase_Natural FROM Dim_Clase_SCD2 WHERE Es_Actual = 1")
dim_clase_lookup = {row[1]: row[0] for row in cursor.fetchall()}

for _, row in df.iterrows():
    id_tiempo = dim_tiempo_lookup.get(row['salida_dt'].date() if pd.notna(row['salida_dt']) else None, 1)
    id_aerolinea = dim_aero_lookup.get(row['cod_aerolinea'], 1)
    id_origen = dim_aeropuerto_lookup.get(row['origen'], 1)
    id_destino = dim_aeropuerto_lookup.get(row['destino'], 1)
    id_pasajero = dim_pasajero_lookup.get(row['uuid_pasajero'], 1)
    id_clase_sk = dim_clase_lookup.get(row['clase'], 1)
    
    cursor.execute("""
        INSERT INTO Hechos_Vuelos (
            ID_Tiempo, ID_Aerolinea, ID_Aeropuerto_Origen, ID_Aeropuerto_Destino, 
            ID_Pasajero, ID_Clase_Sk, Numero_Vuelo, Estado_Vuelo, Duracion_Minutos, 
            Retraso_Minutos, Canal_Venta, Metodo_Pago, Precio_Original, Moneda_Original, 
            Precio_USD, Equipaje, Prioridad
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, 
    id_tiempo, id_aerolinea, id_origen, id_destino, id_pasajero, id_clase_sk,
    str(row['num_vuelo']), row['estado'], int(row['duracion']), int(row['retraso']),
    row['canal'], row['metodo_pago'],
    float(row['precio_orig']) if pd.notna(row['precio_orig']) else 0.0, 
    row['moneda'],
    float(row['precio_usd']) if pd.notna(row['precio_usd']) else 0.0,
    int(row['equipaje']), int(row['prioridad'])
    )

conn.commit()
cursor.close()
conn.close()