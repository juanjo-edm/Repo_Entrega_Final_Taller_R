# Organización de los Datos

En esta carpeta se almacena la información estructurada del proyecto, separando rigurosamente los insumos crudos (`raw/`) provenientes de fuentes oficiales y de web scraping, de las bases depuradas y paneles analíticos (`processed/`).

---

## 1. Estructura de Carpetas

```text
data/
├── raw/                                           # Datos crudos tal como se descargan de las fuentes
│   ├── delitos/                                   # Capa oficial y conteos SDSCJ / SIEDCO
│   │   └── localidades_bogota_raw.geojson         # 21 polígonos y 12 modalidades DAI (2018–2026 corte Sep)
│   ├── poblacion/                                 # Proyecciones demográficas de la Secretaría de Salud
│   │   └── poblacion_localidades_raw.parquet      # 131.502 registros desagregados (2005–2035)
│   └── noticias/                                  # Ingesta consolidada de prensa (Google News RSS)
│       ├── noticias_google_news_consolidado.parquet # Base consolidada y enriquecida (3.916 noticias)
│       └── noticias_google_news_consolidado.rds     # Respaldo en formato binario RDS
└── processed/                                     # Datos listos y normalizados (1 archivo por script)
    ├── 01_delitos/
    │   └── delitos_localidad_anual.parquet        # Conteo anual oficial de denuncias
    ├── 02_poblacion/
    │   └── panel_delitos_poblacion_localidad.parquet # Tasas por 100k hab (19 locs x 5 años)
    ├── 03_noticias/
    │   └── noticias_procesadas.parquet            # Corpus depurado con 11 DAI y métricas NLP
    ├── panel_consolidado_localidad_anual.parquet  # Fusión de tasas oficiales y sentimiento mediático
    ├── clusters_localidades_kmeans.parquet        # Perfiles de agrupamiento espacial K-means
    └── datos_consolidados_shiny.rds               # Insumo empaquetado para app/
```

---

## 2. Fuentes Oficiales

| Dominio | Entidad | Insumo Crudo | Formato |
| :--- | :--- | :--- | :--- |
| **Delitos de Alto Impacto** | Secretaría de Seguridad (SDSCJ / SIEDCO) | `data/raw/delitos/localidades_bogota_raw.geojson` | GeoJSON vectorial |
| **Proyecciones de Población** | Secretaría de Salud (SDS) | `data/raw/poblacion/poblacion_localidades_raw.parquet` | Apache Parquet |
| **Prensa Digital** | Google News RSS | `data/raw/noticias/noticias_google_news_consolidado.parquet` | Apache Parquet / RDS |

---

## 3. Reproducibilidad
Para reconstruir o actualizar los datos procesados a partir de los insumos crudos, ejecute los módulos de `scripts/` de forma secuencial (ver detalle en [`scripts/README.md`](file:///scripts/README.md)).
