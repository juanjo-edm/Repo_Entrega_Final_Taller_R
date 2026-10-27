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
└── processed/                                     # Datos listos y normalizados para modelado
    ├── hurtos/                                    # Paneles armonizados de tasas y delitos
    │   ├── panel_delitos_poblacion_localidad.parquet
    │   └── panel_consolidado_localidad_anual.parquet
    └── noticias/                                  # Corpus clasificado y con métricas de sentimiento
        ├── noticias_procesadas.parquet
        ├── noticias_con_sentimiento.parquet
        ├── noticias_dai.parquet                   # 3.122 artículos estrictamente reclasificados a 11 DAI
        └── noticias_excluidas_no_dai.parquet      # 547 artículos descartados por ruido temático
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
Para reconstruir o actualizar los datos procesados a partir de los insumos crudos, ejecute desde la raíz del proyecto:
```r
source(here::here("scripts", "master.R"))
```
