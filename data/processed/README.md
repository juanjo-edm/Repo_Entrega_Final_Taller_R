# Datos Procesados (`data/processed/`)

Esta carpeta contiene los conjuntos de datos limpios, transformados y enriquecidos del proyecto **Hurtos y Sentimiento Mediático en Bogotá (2022-2026)**.

---

## 1. Principio de Organización: 1 Script = 1 Archivo

La estructura de `data/processed/` es estrictamente simétrica con los módulos de código de `scripts/`. Cada script de procesamiento genera **exactamente un archivo**:

```text
data/processed/
├── README.md
├── 01_delitos/
│   └── delitos_localidad_anual.parquet               # (1) Generado por scripts/02_procesamiento/01_delitos/
├── 02_poblacion/
│   └── panel_delitos_poblacion_localidad.parquet     # (2) Generado por scripts/02_procesamiento/02_poblacion/
├── 03_noticias/
│   └── noticias_procesadas.parquet                   # (3) Generado por scripts/02_procesamiento/03_noticias/
├── panel_consolidado_localidad_anual.parquet         # (4) Generado por scripts/03_analisis_sentometrics.R
├── clusters_localidades_kmeans.parquet               # (5) Generado por scripts/04_clustering_kmeans.R
└── datos_consolidados_shiny.rds                      # (6) Generado por scripts/05_export_insumos_shiny.R
```

---

## 2. Correspondencia Script $\rightarrow$ Archivo

| Script Generador | Archivo Producido | Formato | Descripción |
| :--- | :--- | :---: | :--- |
| `02_procesamiento/01_delitos/procesamiento_delitos.R` | `01_delitos/delitos_localidad_anual.parquet` | Parquet | Conteo anual oficial de denuncias de hurto (personas, residencias, motos) por localidad (19 locs $\times$ 5 años = 95 filas). |
| `02_procesamiento/02_poblacion/procesamiento_poblacion.R` | `02_poblacion/panel_delitos_poblacion_localidad.parquet` | Parquet | Panel oficial que integra la población proyectada SDS y computa tasas de hurto estandarizadas por cada 100.000 habitantes. |
| `02_procesamiento/03_noticias/procesamiento_noticias.R` | `03_noticias/noticias_procesadas.parquet` | Parquet | Microdatos de prensa limpios (3.916 noticias) con métricas de longitud léxica y clasificación oficial en 11 Delitos de Alto Impacto (SDSCJ). |
| `03_analisis_sentometrics.R` | `panel_consolidado_localidad_anual.parquet` | Parquet | Panel balanceado final que fusiona las tasas delictivas con los índices de polaridad de sentimiento NRC por localidad-año. |
| `04_clustering_kmeans.R` | `clusters_localidades_kmeans.parquet` | Parquet | Asignación de conglomerados espaciales ($K^* = 3$) y perfiles de criticidad delictiva. |
| `05_export_insumos_shiny.R` | `datos_consolidados_shiny.rds` | RDS | Objeto consolidado binario que integra indicadores, series temporales, perfiles de clúster y geometrías poligonales para la app. |

---

## 3. Auditoría de Calidad e Integridad

Todas las tablas procesadas cumplen con los siguientes controles automáticos:
```r
# 1. Integridad dimensional del panel de tasas (19 localidades x 5 años)
stopifnot(nrow(arrow::read_parquet(here::here("data", "processed", "02_poblacion", "panel_delitos_poblacion_localidad.parquet"))) == 95)

# 2. Ausencia de valores nulos en tasas clave
stopifnot(all(!is.na(arrow::read_parquet(here::here("data", "processed", "02_poblacion", "panel_delitos_poblacion_localidad.parquet"))$tasa_hurto_personas)))

# 3. Integridad del microdato de prensa
stopifnot(nrow(arrow::read_parquet(here::here("data", "processed", "03_noticias", "noticias_procesadas.parquet"))) == 3916)

# 4. Integridad del panel consolidado final
stopifnot(nrow(arrow::read_parquet(here::here("data", "processed", "panel_consolidado_localidad_anual.parquet"))) == 95)
```
