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
└── processed/                                     # Datos listos y artefactos analíticos
    ├── 01_delitos/
    │   └── delitos_localidad_anual.parquet        # Conteo anual oficial de denuncias (95 filas)
    ├── 02_poblacion/
    │   └── panel_delitos_poblacion_localidad.parquet # Tasas por 100k hab (19 locs × 5 años)
    ├── 03_noticias/
    │   └── noticias_procesadas.parquet            # Corpus depurado con 11 DAI y métricas NLP (3.916 filas)
    ├── 01_sento_corpus.rds                        # Objeto sento_corpus (26 features sin '-')
    ├── 02_lexicons_es.rds                         # Léxicos nrc_es, crimen_es y valencia
    ├── 03_sentiment_scores.rds                    # Puntajes documentales proportionalPol
    ├── 04_peak_docs.rds                           # Noticias extremas (peakdocs)
    ├── 05_sento_measures.rds                      # 364 series mensuales (lag = 6)
    ├── 06_measures_long.rds / 06_measures_wide.rds # Series continuas en formato long y wide
    ├── 07_global_index.rds                        # Índice global distrital y peakdates
    ├── 08_attributions.rds                        # Modelo Elastic Net (BIC) y atribuciones
    ├── panel_consolidado_localidad_anual.parquet  # Fusión anual de tasas y sentimiento (95 × 20)
    ├── clusters_localidades_kmeans.parquet        # Perfiles espaciales K-Means (K* = 3)
    └── datos_consolidados_shiny.rds               # Insumo empaquetado para app/app.R
```

Para consultar la definición campo por campo, llaves primarias y linaje completo de cada tabla o artefacto `.rds`, consulte el [**Diccionario de Datos (`docs/diccionario_datos/`)**](../docs/diccionario_datos/README.md) y [`data/processed/README.md`](processed/README.md).

---

## 2. Fuentes Oficiales

| Dominio | Entidad | Insumo Crudo | Formato |
| :--- | :--- | :--- | :--- |
| **Delitos de Alto Impacto** | Secretaría de Seguridad (SDSCJ / SIEDCO) | `data/raw/delitos/localidades_bogota_raw.geojson` | GeoJSON vectorial |
| **Proyecciones de Población** | Secretaría de Salud (SDS) | `data/raw/poblacion/poblacion_localidades_raw.parquet` | Apache Parquet |
| **Prensa Digital** | Google News RSS | `data/raw/noticias/noticias_google_news_consolidado.parquet` | Apache Parquet / RDS |

---

## 3. Reproducibilidad
Para reconstruir o actualizar los datos procesados a partir de los insumos crudos, ejecute los módulos de `scripts/` de forma secuencial (ver detalle en [`scripts/README.md`](../scripts/README.md)).
