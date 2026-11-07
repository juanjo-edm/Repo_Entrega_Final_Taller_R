# Datos Procesados (`data/processed/`)

Esta carpeta contiene los conjuntos de datos limpios, transformados y enriquecidos del proyecto **Hurtos y Sentimiento Mediático en Bogotá (2022–2026)**, así como los 8 artefactos S3 del contrato de `sentometrics`.

---

## 1. Estructura de Archivos en `data/processed/`

```text
data/processed/
├── README.md
├── 01_delitos/
│   └── delitos_localidad_anual.parquet               # Conteo oficial anual de hurtos (19 locs × 5 años)
├── 02_poblacion/
│   └── panel_delitos_poblacion_localidad.parquet     # Tasas por 100.000 habitantes (SIEDCO + SDS)
├── 03_noticias/
│   └── noticias_procesadas.parquet                   # Microdatos de prensa limpios (3.916 noticias, 11 DAI)
├── 01_sento_corpus.rds                               # [T-07] Objeto S3 sento_corpus (26 features sin '-')
├── 02_lexicons_es.rds                                # [T-09] Objeto S3 sento_lexicons (nrc_es + crimen_es + valenceIn)
├── 03_sentiment_scores.rds                           # [T-10] Objeto S3 sentiment (how = 'proportionalPol')
├── 04_peak_docs.rds                                  # [T-11] Noticias pico y catálogo filtrable (peakdocs)
├── 05_sento_measures.rds                             # [T-13] Objeto S3 sento_measures (364 series mensuales)
├── 06_measures_long.rds                              # [T-14] Series en formato long (18.928 filas) y wide
├── 07_global_index.rds                               # [T-15] Índice global distrital y fechas pico (peakdates)
├── 08_attributions.rds                               # [T-17] Modelo Elastic Net (sento_model) y atribuciones
├── panel_consolidado_localidad_anual.parquet         # Fusión anual de tasas delictivas y sentimiento
├── clusters_localidades_kmeans.parquet               # Asignaciones de clústeres K-Means (K* = 3)
└── datos_consolidados_shiny.rds                      # Bundle integral pre-computado para app/app.R
```

---

## 2. Diccionario de Objetos S3 y Tablas Procesadas

| Script Generador | Archivo Producido | Clase / Formato | Descripción Técnica |
| :--- | :--- | :---: | :--- |
| `02_procesamiento/01_delitos/procesamiento_delitos.R` | `01_delitos/delitos_localidad_anual.parquet` | Parquet | Conteo anual oficial de denuncias de hurto (personas, residencias, motos) por localidad (95 filas). |
| `02_procesamiento/02_poblacion/procesamiento_poblacion.R` | `02_poblacion/panel_delitos_poblacion_localidad.parquet` | Parquet | Panel oficial que integra la población proyectada SDS y calcula tasas de hurto por cada 100.000 habitantes. |
| `02_procesamiento/03_noticias/procesamiento_noticias.R` | `03_noticias/noticias_procesadas.parquet` | Parquet | Corpus de 3.916 noticias depuradas con clasificación jerárquica en los 11 Delitos de Alto Impacto (SDSCJ) y puntuaciones de sentimiento. |
| `04_clustering_kmeans.R` | `clusters_localidades_kmeans.parquet` | Parquet | Asignación determinística de conglomerados ($K^* = 3$, silueta $= 0.5416$): *Céntrico e Institucional*, *Comercial y Automotor* y *Residencial y Periférico*. |
| `03_analisis_sentometrics.R` | `01_sento_corpus.rds` | `sento_corpus` | Corpus estructurado con 26 features binarias `[0, 1]` (19 localidades + 3 clústeres + 4 tópicos DAI) sin guiones medios (`-`). |
| `03_analisis_sentometrics.R` | `02_lexicons_es.rds` | `sento_lexicons` | Diccionarios `nrc_es` y `crimen_es` integrados con modificadores de valencia contextual (`valenceIn`, $t \in \{1, 2, 3, 4\}$). |
| `03_analisis_sentometrics.R` | `03_sentiment_scores.rds` | `sentiment` | Puntuaciones documentales calculadas con `how = "proportionalPol"` y validación cruzada frente a `TFIDF`. |
| `03_analisis_sentometrics.R` | `04_peak_docs.rds` | `list` / `data.table` | Documentos críticos extraídos con `peakdocs()` (globales y locales) enriquecidos con metadatos editoriales. |
| `03_analisis_sentometrics.R` | `05_sento_measures.rds` | `sento_measures` | Panel de 364 series mensuales (`howWithin = "proportionalPol"`, `howDocs = "proportional"`, `howTime = c("linear", "exponential", "beta")`, `lag = 6`). |
| `03_analisis_sentometrics.R` | `06_measures_long.rds` | `list` (`long`/`wide`) | Series continuas auditadas con `measures_fill()` y remodeladas a 18.928 filas en formato largo para visualización interactiva. |
| `03_analisis_sentometrics.R` | `07_global_index.rds` | `list` / `data.table` | Índice global ponderado (`aggregate(..., do.global = TRUE)`) y fechas históricas de alarma social (`peakdates()`). |
| `03_analisis_sentometrics.R` | `08_attributions.rds` | `list` (`sento_model`) | Regresión penalizada Elastic Net ($\alpha = 0.2$, selección BIC, $R^2 = 0.8753$) y descomposición de atribuciones (`features`, `lexicons`, `time`). |
| `03_analisis_sentometrics.R` | `panel_consolidado_localidad_anual.parquet` | Parquet | Panel balanceado final (95 filas) que fusiona tasas delictivas oficiales e indicadores anuales de sentimiento mediático. |
| `05_export_insumos_shiny.R` | `datos_consolidados_shiny.rds` | RDS | Bundle consolidado con paneles, geometrías `sf` (`EPSG:4326`) y objetos `sentometrics` listos para carga inmediata en Shiny. |

---

## 3. Auditoría de Calidad e Integridad

```r
# 1. Integridad dimensional del panel de tasas (19 localidades x 5 años)
stopifnot(nrow(arrow::read_parquet(here::here("data", "processed", "02_poblacion", "panel_delitos_poblacion_localidad.parquet"))) == 95)

# 2. Integridad del microdato de prensa
stopifnot(nrow(arrow::read_parquet(here::here("data", "processed", "03_noticias", "noticias_procesadas.parquet"))) == 3916)

# 3. Existencia de los 8 artefactos .rds de sentometrics y bundle Shiny
stopifnot(all(file.exists(here::here("data", "processed", c(
  "01_sento_corpus.rds", "02_lexicons_es.rds", "03_sentiment_scores.rds",
  "04_peak_docs.rds", "05_sento_measures.rds", "06_measures_long.rds",
  "07_global_index.rds", "08_attributions.rds", "datos_consolidados_shiny.rds"
)))))
```
