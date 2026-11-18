# Datos Procesados (`data/processed/`)

Esta carpeta contiene los conjuntos de datos limpios, transformados y enriquecidos del proyecto **Hurtos y Sentimiento Mediático en Bogotá (2022–2026)**, junto con los 2 artefactos `.rds` consolidados del pipeline (`sentometrics_pipeline.rds` y `datos_consolidados_shiny.rds`).

---

## 1. Estructura de Archivos en `data/processed/`

```text
data/processed/
├── README.md
├── 01_delitos/
│   └── delitos_localidad_mensual.parquet             # Conteo oficial mensual de hurtos SIEDCO (1.083 filas: 19 × 57)
├── 02_poblacion/
│   └── panel_delitos_poblacion_mensual.parquet       # Tasas mensuales por 100.000 habitantes (SIEDCO + SDS, 1.083 × 13)
├── 03_noticias/
│   └── noticias_procesadas.parquet                   # Microdatos de prensa limpios (3.916 filas; 993 en es_objetivo_3mod)
├── sentometrics_pipeline.rds                         # Bundle único S3 (corpus 993 docs, 6 features, 36 series, Elastic Net)
├── panel_consolidado_localidad_anual.parquet         # Fusión anual de tasas delictivas y sentimiento objetivo (95 × 20)
├── clusters_localidades_kmeans.parquet               # Asignaciones de clústeres K-Means (K* = 3; 13 / 5 / 1)
└── datos_consolidados_shiny.rds                      # Bundle integral pre-computado para app/app.R
```

---

## 2. Diccionario de Objetos S3 y Tablas Procesadas

| Script Generador | Archivo Producido | Clase / Formato | Descripción Técnica |
| :--- | :--- | :---: | :--- |
| `02_procesamiento/01_delitos/procesamiento_delitos.R` | `01_delitos/delitos_localidad_mensual.parquet` | Parquet | Conteo mensual oficial de denuncias de hurto (`hurto_personas`, `hurto_residencias`, `hurto_motos`) desde `SIEDCO.csv` (`1.083` filas: 19 locs × 57 meses). |
| `02_procesamiento/02_poblacion/procesamiento_poblacion.R` | `02_poblacion/panel_delitos_poblacion_mensual.parquet` | Parquet | Panel mensual que integra la población proyectada SDS y calcula tasas mensuales por cada 100.000 habitantes (`1.083 × 13`). |
| `02_procesamiento/03_noticias/procesamiento_noticias.R` | `03_noticias/noticias_procesadas.parquet` | Parquet | Corpus de `3.916` noticias depuradas con clasificación jerárquica SDSCJ (`delito_sdscj`), bandera `es_objetivo_3mod` (`993` objetivo) y puntuaciones auxiliares de sentimiento. |
| `04_clustering_kmeans.R` | `clusters_localidades_kmeans.parquet` | Parquet | Asignación determinística de conglomerados ($K^* = 3$, silueta $= 0.5211$, `0` siluetas negativas): *Residencial y Periférico* (`13`), *Céntrico e Institucional* (`5`) y *Comercial y Automotor* (`1`: Los Mártires). |
| `03_analisis_sentometrics.R` | `sentometrics_pipeline.rds` | `list` (9 slots S3) | Contiene en un único archivo: `corpus_sento` (`993` docs × `6` features sin `-`), `lexicons_es` (`nrc_es` + `crimen_es` + valencia), `sentiment_scores` (`proportionalPol`), `peak_docs`, `sento_measures` (`36` series mensuales: `2 × 6 × 3` esquemas `linear`/`exponential0.5`/`beta22`, `lag = 6`), `measures_long` (`1.872` filas), `global_index` + `peakdates()`, `attributions` (Elastic Net $\alpha^* = 0.5$, $\lambda^* = 0.2521$, $R^2 = 0.8899$, $\text{RMSE} = 9.777$, `25/36` activas frente a la tasa mensual real de `SIEDCO.csv`) y `meta`. |
| `03_analisis_sentometrics.R` | `panel_consolidado_localidad_anual.parquet` | Parquet | Panel balanceado final (`95` filas × `20` cols) que fusiona tasas delictivas anualizadas de SIEDCO e indicadores anuales de sentimiento calculados sobre las `993` noticias objetivo. |
| `05_export_insumos_shiny.R` | `datos_consolidados_shiny.rds` | RDS | Bundle consolidado de `13` componentes con paneles, geometrías `sf` (`EPSG:4326`) y objetos `sentometrics` listos para carga inmediata en Shiny. |

> 📖 Para consultar tipos de dato, rangos observados, nulabilidad, llaves primarias (`PK`/`FK`) y el diagrama entidad-relación completo, consulte el [**Diccionario de Datos (`docs/diccionario_datos/`)**](../../docs/diccionario_datos/README.md).

---

## 3. Auditoría de Calidad e Integridad

```r
# 1. Integridad dimensional del panel mensual de tasas (19 localidades x 57 meses)
stopifnot(nrow(arrow::read_parquet(here::here("data", "processed", "02_poblacion", "panel_delitos_poblacion_mensual.parquet"))) == 1083)

# 2. Integridad del microdato de prensa
noti <- arrow::read_parquet(here::here("data", "processed", "03_noticias", "noticias_procesadas.parquet"))
stopifnot(nrow(noti) == 3916, sum(noti$es_objetivo_3mod, na.rm = TRUE) == 993)

# 3. Existencia de los 2 artefactos .rds consolidados (sentometrics y bundle Shiny)
stopifnot(all(file.exists(here::here("data", "processed", c(
  "sentometrics_pipeline.rds",
  "datos_consolidados_shiny.rds"
)))))
```

> ⬅️ Volver al [índice de datos](../README.md) | Ir al [README principal](../../README.md)
