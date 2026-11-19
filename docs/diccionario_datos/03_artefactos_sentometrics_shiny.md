# Capa 3: Artefactos `sentometrics`, Modelo Elastic Net y Bundle Shiny (`data/processed/*.rds`)

Esta capa documenta los **2 artefactos `.rds` consolidados** en `data/processed/`: el bundle completo de `sentometrics` (`sentometrics_pipeline.rds`, que reemplaza los ocho archivos fragmentados anteriores) y el paquete optimizado para la interfaz web (`datos_consolidados_shiny.rds`).

* **Capa anterior:** [`02_tablas_procesadas.md`](./02_tablas_procesadas.md)
* **Índice del diccionario:** [`README.md`](./README.md)
* **Siguiente capa:** [`04_tablas_salida.md`](./04_tablas_salida.md)

---

## Tabla de Contenido

1. [`sentometrics_pipeline.rds`](#1-sentometrics_pipelinerds) — Artefacto S3 consolidado de corpus, sentimiento, `36` series, índice global y Elastic Net (`9` slots)
   * [1.1 `corpus_sento`](#11-corpus_sento-objeto-sento_corpus) (`993` noticias objetivo × `6` features)
   * [1.2 `lexicons_es`](#12-lexicons_es-objeto-sento_lexicons) (`nrc_es`, `crimen_es` y valencia)
   * [1.3 `sentiment_scores`](#13-sentiment_scores-993--15) (`proportionalPol`)
   * [1.4 `peak_docs`](#14-peak_docs) (`993` en tabla completa, `209` críticas)
   * [1.5 `sento_measures`](#15-sento_measures-52--37) (`36` series mensuales)
   * [1.6 `measures_long`](#16-measures_long-1872--9-y-52--37) (`long` y `wide`)
   * [1.7 `global_index`](#17-global_index-52--7) (`serie_global` y `peakdates`)
   * [1.8 `attributions`](#18-attributions-elastic-net-h--1) (modelo Elastic Net BIC y atribuciones)
   * [1.9 `meta`](#19-meta) (metadatos de trazabilidad del pipeline)
2. [`datos_consolidados_shiny.rds`](#2-datos_consolidados_shinyrds) — Bundle integral de `13` componentes para `app/app.R`

---

## Convención de Ejes y Nomenclatura de Series en `sentometrics`

Para garantizar parsimonia econométrica ($M = 36 < N = 51$ observaciones mensuales) y alineación estricta con `SIEDCO.csv`, `sentometrics_pipeline.rds` multiplica tres ejes sobre el **corpus objetivo de `993` noticias** (`Hurto a personas` `736`, `Hurto a residencias` `141`, `Hurto de motocicletas` `116`):

* **2 léxicos (`<lexicon>`):** `nrc_es` (léxico emocional general en español, `4.388` palabras) y `crimen_es` (léxico especializado en seguridad urbana y criminalidad en Bogotá, `105` términos).
* **6 características binarias `[0, 1]` (`<feature>`):**
  * **3 clústeres territoriales:** `c_centro` (`5` locs.), `c_comercial` (`1` loc.: Los Mártires), `c_residencial` (`13` locs.).
  * **3 modalidades de hurto objetivo (`tema_*`):** `tema_hurto_personas`, `tema_hurto_residencias`, `tema_hurto_motos`.
* **3 esquemas de ponderación temporal con ventana `lag = 6` meses (`<time>`):** `linear`, `exponential0.5`, `beta22`.

> **Regla crítica de nomenclatura:** Las 6 características omiten deliberadamente el carácter guion (`-`) porque `sentometrics` usa `--` como separador interno en identificadores compuestos (`<lexicon>--<feature>` y `<lexicon>--<feature>--<time>`), generando exactas **`2 × 6 × 3 = 36` series mensuales**.

---

## 1. `sentometrics_pipeline.rds`

* **Ruta relativa:** `data/processed/sentometrics_pipeline.rds`
* **Formato / Clase en R:** Lista nombrada (`list`) con **`9` componentes** autocontenidos.
* **Propósito y uso:** Concentra en un solo artefacto binario toda la ejecución NLP y econométrica generada por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R), evitando la proliferación de archivos `.rds` sueltos y garantizando coherencia de lectura para [`scripts/06_descriptivos_corpus.R`](../../scripts/06_descriptivos_corpus.R) y [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R).

```r
pipe <- readRDS(here::here("data", "processed", "sentometrics_pipeline.rds"))
names(pipe)
```

### 1.1 `corpus_sento` (Objeto `sento_corpus`)

* **Clase S3:** `sento_corpus`, `corpus` (`quanteda`), `993` textos filtrados donde `es_objetivo_3mod == TRUE` (`993 × 10` `docvars`).
* **Texto de análisis:** `str_squish(paste(titulo, resumen, str_sub(cuerpo, 1, 800), sep = ". "))`.

| Campo en `docvars` | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `date` | `Date` | No nula (`0 NA`) | `[2022-01-01, 2026-09-30]` | Fecha de publicación de cada noticia objetivo. |
| `c_centro`, `c_comercial`, `c_residencial` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` (partición mutuamente excluyente) | Indicadores del clúster territorial $K$-means de la localidad. |
| `tema_hurto_personas`, `tema_hurto_residencias`, `tema_hurto_motos` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` (3 modalidades comparables con SIEDCO) | Indicadores binarios de las modalidades objetivo de hurto. |

### 1.2 `lexicons_es` (Objeto `sento_lexicons`)

* **Clase S3:** `sento_lexicons` (`list` de `3` tablas `data.table` y atributo `valence_table_full`).

| Elemento / Atributo | Dimensiones / Clase | Dominio observado | Descripción |
| :--- | :---: | :--- | :--- |
| `nrc_es` | `4.388 × 2` (`data.table`) | `y ∈ [-1, 1]` | Léxico emocional NRC adaptado al español. |
| `crimen_es` | `105 × 2` (`data.table`) | `y ∈ [-1, 0,9]` | Léxico específico del dominio de seguridad urbana en Bogotá. |
| `valence` | `30 × 2` (`data.table`) | `y ∈ [-1, 1,8]` | Modificadores contextuales sin columna `t` requeridos por `sento_lexicons()`. |
| `attr(..., "valence_table_full")` | `30 × 3` (`data.frame`) | `t ∈ {1, 2, 3, 4}` (`8` negadores, `12` amplif., `6` atenuad., `4` advers.) | Versión completa con tipo `t` para auditoría y Shiny. |

### 1.3 `sentiment_scores` (`993 × 15`)

* **Clase S3:** `sentiment`, `data.table`, `data.frame` (más atributo `comparacion_metodologica`).
* **Llave primaria (`PK`):** `id` (subconjunto de `doc_*` correspondiente a las `993` noticias objetivo).

| Campo / Atributo | Tipo (`R`) | Dominio / Valores observados | Descripción |
| :--- | :---: | :--- | :--- |
| `id`, `date`, `word_count` | `character`, `Date`, `numeric` | `993` documentos objetivo | Identificador, fecha y tokens procesados. |
| `nrc_es--<feature>` (`6` cols) | `numeric` | Puntajes `proportionalPol` | Sentimiento bajo `nrc_es` en las 6 características. |
| `crimen_es--<feature>` (`6` cols) | `numeric` | Puntajes `proportionalPol` | Sentimiento bajo `crimen_es` en las 6 características. |
| `attr(..., "comparacion_metodologica")` | `list` (`4` escalares) | `correlacion_propPol_tfidf = 0,7285`, `media_nrc_es = -0,1192`, `media_crimen_es = -0,4076`, `media_combinada = -0,2634` | Comparación metodológica de `proportionalPol` frente a `TFIDF` en el corpus objetivo. |

### 1.4 `peak_docs`

* **Estructura (`5` slots):** `peak_ids_both` (`25`), `peak_ids_neg` (`25`), `peak_ids_pos` (`25`), `tabla_completa` (`993 × 21`) y `top_criticas` (`209 × 21`).
* **Distribución de `tipo_pico` en `tabla_completa` (`993`):** `"Regular"` (`784`), `"Extremo Negativo Local"` (`87`), `"Extremo Positivo Local"` (`72`), `"Pico Negativo Global"` (`25`), `"Pico Positivo Global"` (`25`). `es_pico_global == TRUE` suma `50` artículos (`943` `FALSE`).

### 1.5 `sento_measures` (`52 × 37`)

* **Clase S3:** `sento_measures` (`list` de `8` slots): series mensuales (`by = "month"`, `lag = 6`, `fill = "zero"`), cubriendo **`52` meses efectivos (`2022-06-01` a `2026-09-01`)** × **`36` series (`2 × 6 × 3`)**.

| Slot | Dimensiones | Contenido |
| :--- | :---: | :--- |
| `measures` | `52 × 37` (`data.table`) | Columna `date` + `36` series `<lexicon>--<feature>--<time>`. |
| `features` | `character(6)` | `c("c_centro", "c_comercial", "c_residencial", "tema_hurto_personas", "tema_hurto_residencias", "tema_hurto_motos")`. |
| `lexicons` | `character(2)` | `c("nrc_es", "crimen_es")`. |
| `time` | `character(3)` | `c("linear", "exponential0.5", "beta22")`. |
| `stats` | `matrix` (`5 × 36`) | `mean`, `sd`, `max`, `min`, `meanCorr`. |
| `attribWeights` | `list(W, B)` | Pesos documentales (`993` docs × `52` meses) y matriz de rezagos (`6 × 3`). |

### 1.6 `measures_long` (`1.872 × 9` y `52 × 37`)

* **`measures_long$long`:** `1.872` filas (`52 meses × 36 series`) × `9` columnas (`date`, `serie_id`, `lexicon`, `feature`, `time`, `valor ∈ [-1, 0,7223]`, `grupo_feature` en `"Clúster Territorial"` [`936`] / `"Modalidad de Hurto"` [`936`], `feature_label`, `lexicon_label`).
* **`measures_long$wide`:** `52 × 37` (`data.table`), copia exacta de `sento_measures$measures`.

### 1.7 `global_index` (`52 × 7`)

* **`serie_global` (`52 × 7`):** `date` (`2022-06-01`..`2026-09-01`), `globLex ∈ [-0,2852, -0,0085]`, `globFeat ∈ [-0,0951, -0,0028]`, `globTime ∈ [-0,1902, -0,0057]`, `global ∈ [-0,1902, -0,0057]`, `es_pico` (`TRUE = 8`, `FALSE = 44`), `tipo_pico` (`"Normal"` `39`, `"Pico de Alarma / Negatividad"` `8`, `"Pico Positivo / Operatividad"` `5`). Incluye además vectores `Date(8)` `peakdates_both`, `peakdates_neg`, `peakdates_pos`.

### 1.8 `attributions` (Elastic Net `h = 1`)

* **Variable dependiente ($y_{t+1}$):** Tasa mensual real agregada de hurto distrital calculada directamente desde `SIEDCO.csv` (`panel_delitos_poblacion_mensual.parquet`) para los `51` pares predictivos (`2022-06-01`..`2026-08-01` $\rightarrow$ `2022-07-01`..`2026-09-01`).
* **Parámetros verificados en `metricas_modelo`:** `alpha_optimo = 0,8`, `lambda_optimo = 0,3341228`, `horizonte_h = 1`, `criterio = "BIC"`, `r2_in_sample = 0,8455`, `rmse = 11,574`, `rmse_oos_en = 24,347`, `rmse_oos_ar1 = 34,713`, `reduccion_rmse_vs_ar1 = 29,9`, `n_observaciones = 51`, `n_predictores = 36`, `n_activos = 21`.

| Slot | Clase / Dimensiones | Rango / Valores observados | Descripción |
| :--- | :---: | :--- | :--- |
| `modelo` | `sento_model` | `36` predictores, intercepto `244,3737` | Modelo Elastic Net estimado por `sento_model()`. |
| `attributions_raw` / `norm` | `attributions` (`5` slots) | `lags` (`51 × 7`), `lexicons` (`51 × 3`), `features` (`51 × 7`), `time` (`51 × 4`), `documents` (`list(51)`) | Contribuciones lineales de cada dimensión por fecha. |
| `attr_long_raw` / `norm` | `data.table` (`561 × 5`) | Bruta: `[-168,2210, 74,5604]`; Norm.: `[-1, 0,4776]` | Versión larga (`51 meses × 11 componentes`: `6` features [`306`], `2` lexicons [`102`], `3` times [`153`]). |
| `ajuste_temporal` | `tbl_df` (`51 × 4`) | `observado ∈ [76,53, 220,42]`, `predicho ∈ [87,06, 210,71]`, `residual ∈ [-32,46, 25,54]` | Observado mensual SIEDCO vs. predicción `h = 1`. |
| `coeficientes` | `tbl_df` (`21 × 2`) | `coeficiente ∈ [-88,2191, 83,3967]` | Las `21` series activas seleccionadas (`β ≠ 0`). |

### 1.9 `meta`

Lista de `7` metadatos de trazabilidad: `fecha_generacion`, `n_noticias_recopiladas = 3916`, `n_noticias_modelo = 993`, `modalidades_objetivo`, `n_features = 6`, `features` y `n_series = 36`.

---

## 2. `datos_consolidados_shiny.rds`

* **Ruta relativa:** `data/processed/datos_consolidados_shiny.rds`
* **Formato / Clase en R:** `list` autocontenida de `13` componentes
* **Propósito y uso:** Empaqueta en un único artefacto ligero todas las tablas, geometrías simplificadas y salidas analíticas necesarias para que el tablero interactivo [`app/app.R`](../../app/app.R) arranque de forma autónoma sin estimar modelos al inicio.
* **Linaje:**
  * **Generado por:** [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) (combinando `panel_consolidado_localidad_anual.parquet`, `clusters_localidades_kmeans.parquet`, `localidades_bogota_raw.geojson` simplificado con `dTolerance = 0.0005` en `EPSG:4326` y `sentometrics_pipeline.rds`).
  * **Consumido por:** [`app/app.R`](../../app/app.R) (único archivo de datos cargado al inicio de la aplicación).

```r
shiny_bundle <- readRDS(here::here("data", "processed", "datos_consolidados_shiny.rds"))
names(shiny_bundle)
```

### 2.1 Inventario de los 13 Componentes y Uso por Pestaña en Shiny

| Slot | Clase / Dimensiones | Origen exacto | Consumo en [`app/app.R`](../../app/app.R) |
| :--- | :---: | :--- | :--- |
| `panel_localidades` | `tbl_df` (`95 × 24`) | `panel_consolidado_localidad_anual` (`20` cols) + `cluster_id`, `cluster_nombre`, `perfil_seguridad`, `silueta_localidad` | Pestañas **1 (Panorama)**, **2 (Mi localidad)**, **3 (Hurto vs. prensa)** y **4 (Clusters)**. |
| `clusters_perfiles` | `tbl_df` (`19 × 11`) | `clusters_localidades_kmeans.parquet` | Perfiles y vista tridimensional en **4 (Clusters)**. |
| `geometrias` | `sf` (`19 × 13`, `WGS 84`) | `localidades_bogota_raw.geojson` unido a `clusters_localidades_kmeans` + `geometry` simplificada | Polígonos base de los mapas Leaflet en **1 (Panorama)** y **4 (Clusters)**. |
| `corpus_stats_mes` | `tbl_df` (`57 × 12`) | `corpus_summarize(corpus_sento, by = "month")$stats` (`documents` `4..46`, `meanTokens` `49,50..169,33`) | Estadísticas mensuales del corpus objetivo en **6 (Datos y método)**. |
| `corpus_stats_anio` | `tbl_df` (`5 × 12`) | `corpus_summarize(corpus_sento, by = "year")$stats` (`documents` `112..282`, `totalTokens` `11.970..36.166`) | Resumen anual del corpus objetivo en **6 (Datos y método)**. |
| `lexicos_info` | `list` (`4`) | `lexicons_es` + `comparacion_metodologica` (`nrc_es`, `crimen_es`, `valence_shifters`) | Referencia metodológica de los léxicos. |
| `peak_docs` | `list` (`5`) | `sentometrics_pipeline.rds$peak_docs` (`tabla_completa` `993 × 21`, `top_criticas` `209 × 21`) | Noticias extremas en **2 (Mi localidad)** y tabla DT en **6 (Datos y método)**. |
| `measures_long` | `tbl_df` (`1.872 × 9`) | `sentometrics_pipeline.rds$measures_long$long` | Selector dinámico de las `36` series mensuales en **5 (Sentometrics y Elastic Net)**. |
| `global_index` | `list` (`4`) | `sentometrics_pipeline.rds$global_index` | `peakdates_neg` marca fechas críticas en **5 (Sentometrics y Elastic Net)**. |
| `attributions` | `list` (`5`) | Subconjunto *tidy* de `sentometrics_pipeline.rds$attributions` | Métricas (`R2 in-sample = 0,8455`, `RMSE OOS = 24,347`), ajuste observado vs. predicho (`SIEDCO.csv`), coeficientes y contribuciones en **5 (Sentometrics y Elastic Net)**. |
| `meta_pipeline` | `list` (`7`) | `sentometrics_pipeline.rds$meta` (`3.916` recopiladas, `993` modelo, `6` features, `36` series) | Trazabilidad y contrato de artefactos en **6 (Datos y método)**. |
| `fecha_generacion` | `POSIXct` (`1`) | `Sys.time()` al exportar | Marca temporal de compilación del bundle. |
| `horizonte` | `character` (`1`) | `"2022-2026"` | Ventana temporal del análisis. |

---

* **Siguiente documento:** [`04_tablas_salida.md`](./04_tablas_salida.md) — Tablas exportadas en `output/tables/*.csv`.
