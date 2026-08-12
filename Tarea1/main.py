import sys
import warnings
import pandas as pd
import matplotlib.pyplot as plt


def df_to_image(df, title, filename):
    fig, ax = plt.subplots(figsize=(12, 8))
    ax.axis('off')
    
    table = ax.table(
        cellText=df.values,
        colLabels=df.columns,
        cellLoc='center',
        loc='center'
    )
    
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1.2, 1.5)
    
    for key, cell in table.get_celld().items():
        if key[0] == 0: # Fila de encabezado
            cell.set_facecolor('#4c72b0')
            cell.set_text_props(color='white', fontweight='bold')
            
    plt.title(title, fontsize=14, fontweight='bold', pad=20)
    plt.savefig(filename, dpi=200, bbox_inches='tight')
    plt.close()


warnings.filterwarnings('ignore', category=UserWarning)

df_original = pd.read_csv('dataset_sucio.csv')

df = df_original.copy()

df.drop_duplicates(subset=['id_cliente'], keep='first', inplace=True)

for col in df.select_dtypes(include=['object']).columns:
    df[col] = df[col].astype(str).str.strip()

df['nombre'] = df['nombre'].str.title()
df['ciudad'] = df['ciudad'].str.title()
df['categoria'] = df['categoria'].str.title()

df.replace({'Nan': '', 'None': ''}, inplace=True)

df['genero'] = df['genero'].str.lower().map({
    'm': 'Masculino', 
    'f': 'Femenino'
})

df['fecha_registro'] = pd.to_datetime(df['fecha_registro'], errors='coerce', dayfirst=False)
mask_fechas_nulas = df['fecha_registro'].isna()
if mask_fechas_nulas.any():
    df.loc[mask_fechas_nulas, 'fecha_registro'] = pd.to_datetime(
        df_original.loc[mask_fechas_nulas, 'fecha_registro'], 
        errors='coerce', 
        dayfirst=True
    )

df['gasto_q'] = df['gasto_q'].astype(str).str.replace(',', '.', regex=False)
df['gasto_q'] = pd.to_numeric(df['gasto_q'], errors='coerce')

df.dropna(subset=['fecha_registro'], inplace=True)

df['genero'].fillna('No especificado', inplace=True)
df['ciudad'].replace('', 'Desconocida', inplace=True)
df['ciudad'].fillna('Desconocida', inplace=True)

df_exportar = df.copy()
df_exportar['gasto_q'].fillna(0.0, inplace=True)
df_exportar.to_csv('dataset_limpio.csv', index=False)

pivot_gasto = pd.pivot_table(
    df, 
    values='gasto_q', 
    index='ciudad', 
    columns='categoria', 
    aggfunc='mean',
    fill_value=0
).round(2)

pivot_clientes = pd.pivot_table(
    df,
    values='id_cliente',
    index='ciudad',
    columns='genero',
    aggfunc='count',
    fill_value=0
)

fig, axes = plt.subplots(1, 2, figsize=(16, 6))

gasto_por_cat = df.groupby('categoria')['gasto_q'].mean().sort_values(ascending=False)
colors_bar = ['#4c72b0', '#55a868', '#c44e52', '#8172b2']

gasto_por_cat.plot(kind='bar', ax=axes[0], color=colors_bar)
axes[0].set_title('Gasto Promedio Real por Categoría')
axes[0].set_ylabel('Quetzales (Q)')
axes[0].set_ylim(0, max(gasto_por_cat) * 1.2) # Margen superior para las etiquetas
axes[0].tick_params(axis='x', rotation=45)

for p in axes[0].patches:
    axes[0].annotate(f"{p.get_height():.1f}", 
                     (p.get_x() + p.get_width() / 2., p.get_height()), 
                     ha='center', va='center', xytext=(0, 9), textcoords='offset points', fontsize=9)

genero_count = df['genero'].value_counts()
colors_pie = ['#4c72b0', '#dd8452', '#55a868']

genero_count.plot(kind='pie', ax=axes[1], autopct='%1.1f%%', startangle=90, colors=colors_pie)
axes[1].set_title('Distribución de Clientes por Género')
axes[1].set_ylabel('')

plt.tight_layout()
plt.savefig('analisis_visual.png', dpi=150)

df_muestra_original = df_original.head(15)
df_to_image(
    df_muestra_original, 
    'Estado Original (Datos Sucios - Muestra)', 
    'estado_original.png'
)

df_muestra_limpio = df_exportar.head(15)
df_to_image(
    df_muestra_limpio, 
    'Estado Depurado (Datos Limpios - Muestra)', 
    'estado_depurado.png'
)