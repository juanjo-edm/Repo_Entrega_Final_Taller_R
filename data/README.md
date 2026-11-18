# Organización de los Datos

En esta carpeta se almacena la información estructurada del proyecto, separando rigurosamente los insumos crudos (`raw/`) provenientes de fuentes oficiales y de web scraping, de las bases depuradas y paneles analíticos (`processed/`).

---

## 1. Estructura de Carpetas

```text
data/
├── raw/                                           # Datos crudos tal como se descargan de las fuentes
│   ├── delitos/                                   # Capa oficial y microdatos SDSCJ / SIEDCO
│   │   ├── SIEDCO.csv                             # Registro mensual de hurtos por localidad (2022–sep 2026)
│   │   └── localidades_bogota_raw.geojson         # Polígonos oficiales SDSCJ de las localidades de Bogotá
│   ├── poblacion/                                 # Proyecciones demográficas de la Secretaría de Salud
│   │   └── poblacion_localidades_raw.parquet      # 131.502 registros desagregados (2005–2035)
│   └── noticias/                                  # Ingesta consolidada de prensa (Google News RSS)
│       ├── noticias_google_news_consolidado.parquet # Base consolidada y enriquecida (3.916 noticias)
│       └── noticias_google_news_consolidado.rds     # Respaldo en formato binario RDS
└── processed/                                     # Datos listos y artefactos analíticos
    ├── 01_delitos/
    │   └── delitos_localidad_mensual.parquet      # Conteo mensual oficial de hurtos (1.083 filas: 19 × 57 meses)
    ├── 02_poblacion/
    │   └── panel_delitos_poblacion_mensual.parquet # Panel mensual delitos + población + tasas/100k (1.083 × 13)
    ├── 03_noticias/
    │   └── noticias_procesadas.parquet            # Corpus depurado (3.916 filas; 993 en es_objetivo_3mod)
    ├── sentometrics_pipeline.rds                  # Bundle consolidado S3: corpus (993 docs, 6 features), 36 series, índice y Elastic Net
    ├── panel_consolidado_localidad_anual.parquet  # Fusión anual de tasas y sentimiento objetivo (95 × 20)
    ├── clusters_localidades_kmeans.parquet        # Perfiles espaciales K-Means (K* = 3; 13 / 5 / 1)
    └── datos_consolidados_shiny.rds               # Insumo empaquetado para app/app.R
```

Para consultar la definición campo por campo, llaves primarias y linaje completo de cada tabla o artefacto `.rds`, consulte el [**Diccionario de Datos (`docs/diccionario_datos/`)**](../docs/diccionario_datos/README.md) y [`data/processed/README.md`](processed/README.md).

---

## 2. Fuentes Oficiales

| Dominio | Entidad | Insumo Crudo | Formato |
| :--- | :--- | :--- | :--- |
| **Delitos de Alto Impacto** | Secretaría de Seguridad (SDSCJ / SIEDCO) | `data/raw/delitos/SIEDCO.csv` y `localidades_bogota_raw.geojson` | CSV + GeoJSON vectorial |
| **Proyecciones de Población** | Secretaría de Salud (SDS) | `data/raw/poblacion/poblacion_localidades_raw.parquet` | Apache Parquet |
| **Prensa Digital** | Google News RSS | `data/raw/noticias/noticias_google_news_consolidado.parquet` | Apache Parquet / RDS |

---

## 3. Reproducibilidad
Para reconstruir o actualizar los datos procesados a partir de los insumos crudos, ejecute los módulos de `scripts/` de forma secuencial (ver detalle en [`scripts/README.md`](../scripts/README.md)).
