# Capa 3: Artefactos `sentometrics`, Modelo Elastic Net y Bundle Shiny (`data/processed/*.rds`)

Esta capa documenta los **9 artefactos analíticos** generados por el pipeline de econometría textual (`01` a `08` en `data/processed/`) y el **bundle consolidado** que alimenta directamente el tablero interactivo en Shiny (`datos_consolidados_shiny.rds`).

* **Capa anterior:** [`02_tablas_procesadas.md`](./02_tablas_procesadas.md)
* **Índice del diccionario:** [`README.md`](./README.md)
* **Siguiente capa:** [`04_tablas_salida.md`](./04_tablas_salida.md)

---

## Tabla de Contenido

1. [`01_sento_corpus.rds`](#1-01_sento_corpusrds) — Objeto `sento_corpus` con 26 variables indicadoras binarias
2. [`02_lexicons_es.rds`](#2-02_lexicons_esrds) — Objeto `sento_lexicons` (`nrc_es`, `crimen_es` y modificadores de valencia)
3. [`03_sentiment_scores.rds`](#3-03_sentiment_scoresrds) — Puntajes documentales `sentiment` (`3.916 × 55`)
4. [`04_peak_docs.rds`](#4-04_peak_docsrds) — Ranking de noticias extremas y picos globales
5. [`05_sento_measures.rds`](#5-05_sento_measuresrds) — Medidas temporales `sento_measures` (`52 × 365`)
6. [`06_measures_long.rds` y `06_measures_wide.rds`](#6-06_measures_longrds-y-06_measures_widerds) — Series temporales en formatos largo y ancho
7. [`07_global_index.rds`](#7-07_global_indexrds) — Índice sintético global de sentimiento mediático (`52 × 7`)
8. [`08_attributions.rds`](#8-08_attributionsrds) — Modelo Elastic Net (`h = 1`) y descomposición de atribuciones
9. [`datos_consolidados_shiny.rds`](#9-datos_consolidados_shinyrds) — Bundle integral de 12 componentes para la app Shiny

---

## Convención de Ejes y Nomenclatura de Series en `sentometrics`

Los objetos `03`, `05`, `06` y `08` organizan sus dimensiones multiplicando tres ejes:

* **2 léxicos (`<lexicon>`):** `nrc_es` (léxico emocional general en español) y `crimen_es` (léxico contextual de seguridad urbana y criminalidad en Bogotá).
* **26 características binarias `[0, 1]` (`<feature>`):**
  * **3 clústeres territoriales:** `c_centro`, `c_comercial`, `c_residencial`.
  * **4 ejes temáticos (`tema_*`):** `tema_hurto_personas`, `tema_hurto_patrimonial`, `tema_violencia_vida`, `tema_institucional`.
  * **19 localidades urbanas (`loc_*`):** `loc_antonio_narino`, `loc_barrios_unidos`, `loc_bosa`, `loc_chapinero`, `loc_ciudad_bolivar`, `loc_engativa`, `loc_fontibon`, `loc_kennedy`, `loc_la_candelaria`, `loc_los_martires`, `loc_puente_aranda`, `loc_rafael_uribe_uribe`, `loc_san_cristobal`, `loc_santa_fe`, `loc_suba`, `loc_teusaquillo`, `loc_tunjuelito`, `loc_usaquen`, `loc_usme`.
* **7 esquemas de ponderación temporal con ventana `lag = 6` meses (`<time>`):** `linear`, `exponential0.2`, `exponential0.5`, `beta12`, `beta13`, `beta22`, `beta23`.

> **Regla crítica de nomenclatura:** Las 26 características omiten deliberadamente el carácter guion (`-`) porque `sentometrics` usa `--` como separador interno en identificadores compuestos (`<lexicon>--<feature>` y `<lexicon>--<feature>--<time>`).

---

## 1. `01_sento_corpus.rds`

* **Ruta relativa:** `data/processed/01_sento_corpus.rds`
* **Clase S3 en R:** `sento_corpus`, `corpus` (`quanteda`), vector de `3.916` textos con metadatos `docvars` (`3.916 × 27`)
* **Unidad de observación:** Artículo individual (`doc_1` .. `doc_3916`), alineado exactamente con `noticias_procesadas.parquet`.
* **Propósito y uso:** Encapsula el texto estructurado de análisis (`str_squish(paste(titulo, resumen, str_sub(cuerpo, 1, 800), sep = ". "))`) junto con la fecha y las 26 variables binarias territoriales y temáticas exigidas por `sentometrics`.
* **Linaje:**
  * **Generado por:** [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R).
  * **Consumido por:** [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R), [`scripts/06_descriptivos_corpus.R`](../../scripts/06_descriptivos_corpus.R), [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) (para calcular `corpus_summarize` mensual y anual) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

```r
corpus_sento <- readRDS(here::here("data", "processed", "01_sento_corpus.rds"))
meta_corpus  <- quanteda::docvars(corpus_sento)
```

| Campo en `docvars` | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `date` | `Date` | No nula (`0 NA`) | `[2022-01-01, 2026-09-30]` | Fecha de publicación de cada documento. |
| `c_centro`, `c_comercial`, `c_residencial` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` (3 columnas) | Indicadores mutuamente excluyentes del clúster territorial $K$-means asignado a la localidad de la nota. |
| `tema_hurto_personas` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` | Indicador binario para noticias de hurto a personas, celulares o bicicletas (`modalidad_dai` correspondiente). |
| `tema_hurto_patrimonial` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` | Indicador binario para hurtos a residencias, comercio, automotores, motocicletas o entidades financieras. |
| `tema_violencia_vida` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` | Indicador binario para homicidio, lesiones personales, violencia intrafamiliar, delitos sexuales y extorsión. |
| `tema_institucional` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` | Indicador binario para notas de fuente `"Institucional"` o excluidas por operatividad/política de seguridad. |
| `loc_antonio_narino` .. `loc_usme` | `numeric` (`0`/`1`) | No nula (`0 NA`) | `{0, 1}` (19 columnas) | Variables indicadoras *one-hot* por localidad urbana (`loc_la_candelaria` conserva el artículo `la_`). |

---

## 2. `02_lexicons_es.rds`

* **Ruta relativa:** `data/processed/02_lexicons_es.rds`
* **Clase S3 en R:** `sento_lexicons` (lista con 3 elementos `data.table` y el atributo `valence_table_full`)
* **Propósito y uso:** Almacena los diccionarios léxicos de polaridad en español y la tabla de modificadores contextuales de valencia (negación, amplificación, atenuación y contraste adversativo) usados en la calificación documental.
* **Linaje:** Generado por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R); consumido por [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) (`lexicos_info`) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

```r
lexicos <- readRDS(here::here("data", "processed", "02_lexicons_es.rds"))
tabla_valencia <- attr(lexicos, "valence_table_full")
```

| Elemento / Atributo | Dimensiones / Clase | Columnas | Rango / Dominio observado | Descripción |
| :--- | :---: | :--- | :--- | :--- |
| `nrc_es` | `4.388 × 2` (`data.table`) | `x` (`character`), `y` (`numeric`) | `y ∈ [-1, 1]` (`6` valores distintos, `0 NA`) | Léxico emocional NRC adaptado al español (polaridades y pesos léxicos generales). |
| `crimen_es` | `105 × 2` (`data.table`) | `x` (`character`), `y` (`numeric`) | `y ∈ [-1, 0,9]` (`12` valores distintos, `0 NA`) | Léxico específico del dominio de seguridad en Bogotá (términos delictivos negativos y de operatividad/judicialización positivos). |
| `valence` | `30 × 2` (`data.table`) | `x` (`character`), `y` (`numeric`) | `y ∈ [-1, 1,8]` (`5` valores distintos, `0 NA`) | Tabla de modificadores léxicos sin columna de tipo requerida por el constructor `sento_lexicons()`. |
| `attr(..., "valence_table_full")` | `30 × 3` (`data.frame`) | `x` (`character`), `y` (`numeric`), `t` (`integer`) | `t ∈ {1, 2, 3, 4}` (`1`: negadores `8`, `2`: amplificadores `12`, `3`: atenuadores `6`, `4`: adversativos `4`) | Versión completa con etiqueta tipológica `t` para documentación e interfaz Shiny. |

---

## 3. `03_sentiment_scores.rds`

* **Ruta relativa:** `data/processed/03_sentiment_scores.rds`
* **Clase S3 en R:** `sentiment`, `data.table`, `data.frame`
* **Dimensiones verificadas:** `3.916` filas × `55` columnas (más atributo `comparacion_metodologica`)
* **Llave primaria (`PK`):** `id` (`"doc_1"` .. `"doc_3916"`)
* **Propósito y uso:** Matriz documental de sentimiento calculada mediante `sentometrics::compute_sentiment()` con esquema `how = "proportionalPol"` y `do.sentence = FALSE`. Cada columna `<lexicon>--<feature>` registra el puntaje asignado cuando el documento pertenece a dicha característica (`0` o `NA` según inactividad de característica en los cruces).
* **Linaje:** Generado por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R); insumo directo para `05_sento_measures.rds` y enriquecimiento de `noticias_procesadas.parquet`.

```r
sent_scores <- readRDS(here::here("data", "processed", "03_sentiment_scores.rds"))
comp_metodo <- attr(sent_scores, "comparacion_metodologica")
```

| Campo / Atributo | Tipo (`R`) | Nulabilidad / Contenido | Dominio / Valores observados | Descripción |
| :--- | :---: | :--- | :--- | :--- |
| `id` | `character` | No nula (`0 NA`) | `"doc_1"` .. `"doc_3916"` (`3.916` únicos) | Identificador único del artículo, pareado 1 a 1 con `noticias_procesadas.parquet`. |
| `date` | `Date` | No nula (`0 NA`) | `[2022-01-01, 2026-09-30]` (`527` únicos) | Fecha de publicación heredada del corpus. |
| `word_count` | `numeric` | No nula (`0 NA`) | `[21, 197]` (`116` únicos) | Conteo de palabras contabilizadas sobre el texto del `sento_corpus`. |
| `nrc_es--<feature>` (`26` cols) | `numeric` | Según pertenencia binaria | Puntajes proporcionales ponderados por valencia | Sentimiento bajo el léxico `nrc_es` proyectado en cada una de las 26 características binarias. |
| `crimen_es--<feature>` (`26` cols) | `numeric` | Según pertenencia binaria | Puntajes proporcionales ponderados por valencia | Sentimiento bajo el léxico `crimen_es` proyectado en cada una de las 26 características binarias. |
| `attr(..., "comparacion_metodologica")` | `list` (`4` escalares) | No nula | `correlacion_propPol_tfidf = 0,7383`, `media_nrc_es = -0,0859`, `media_crimen_es = -0,3063`, `media_combinada = -0,1961` | Métricas comparativas entre el esquema principal (`proportionalPol`) y la alternativa `TFIDF`. |

---

## 4. `04_peak_docs.rds`

* **Ruta relativa:** `data/processed/04_peak_docs.rds`
* **Formato / Clase en R:** `list` de `5` componentes
* **Propósito y uso:** Identifica los artículos más extremos (`peak_docs()` global y umbrales percentiles locales `P5` / `P95`) para inspección cualitativa en el informe y en la pestaña **Datos y método** de Shiny.
* **Linaje:** Generado por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R); consumido por [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

```r
picos_docs <- readRDS(here::here("data", "processed", "04_peak_docs.rds"))
top_criticas <- picos_docs$top_criticas
```

### 4.1 Estructura de la Lista (`5` slots)

| Slot | Clase / Dimensiones | Descripción |
| :--- | :---: | :--- |
| `peak_ids_both` | `character` (longitud `25`) | Los `25` identificadores `id` con mayor magnitud absoluta en `sentometrics::peak_docs(..., type = "both")`. |
| `peak_ids_neg` | `character` (longitud `25`) | Los `25` artículos más extremos en polaridad negativa (`type = "neg"`). |
| `peak_ids_pos` | `character` (longitud `25`) | Los `25` artículos más extremos en polaridad positiva (`type = "pos"`). |
| `tabla_completa` | `data.table` (`3.916 × 21`) | Tabla completa de documentos con variables de clasificación, sentimiento y banderas de pico. |
| `top_criticas` | `data.table` (`229 × 21`) | Subconjunto filtrado de `tabla_completa` donde `tipo_pico != "Regular"`. |

### 4.2 Campos de `tabla_completa` (`3.916 × 21`) y `top_criticas` (`229 × 21`)

Los primeros `19` campos (`id`, `fecha`, `año`, `mes`, `localidad`, `cluster_nombre`, `fuente`, `delito_sdscj`, `modalidad_dai`, `es_dai_estricto`, `confianza_dai`, `titulo`, `resumen`, `enlace`, `word_count`, `score_nrc_es`, `score_crimen_es`, `sentimiento_score`, `sentimiento_categoria`) coinciden en tipo y dominio con [`noticias_procesadas.parquet`](./02_tablas_procesadas.md#3-noticias_procesadasparquet) (presentando `confianza_dai` `794 NA` en `tabla_completa` y `82 NA` en `top_criticas`). Se añaden dos columnas exclusivas:

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Distribución observada | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `es_pico_global` | `logical` | No nula (`0 NA`) | `TRUE` (`49`), `FALSE` (`3.867`) | Marca `TRUE` cuando el artículo pertenece a los picos globales extremos (`peak_ids_neg` o `peak_ids_pos`). |
| `tipo_pico` | `character` | No nula (`0 NA`) | En `tabla_completa`: `"Regular"` (`3.687`), `"Extremo Negativo Local"` (`91`), `"Extremo Positivo Local"` (`89`), `"Pico Negativo Global"` (`25`), `"Pico Positivo Global"` (`24`). `top_criticas` reúne las `229` observaciones distintas de `"Regular"`. | Clasificación jerárquica entre picos globales de `sentometrics` y extremos locales (`sentimiento_score` en percentiles extremos). |

---

## 5. `05_sento_measures.rds`

* **Ruta relativa:** `data/processed/05_sento_measures.rds`
* **Clase S3 en R:** `sento_measures` (`list` de `8` slots)
* **Propósito y uso:** Objeto estructural de series temporales agregadas mensualmente (`by = "month"`, `lag = 6`, `fill = "latest"`) a partir de `03_sentiment_scores.rds`. Al requerir una ventana móvil de 6 meses, los primeros 5 meses quedan descartados y las series cubren **`52` meses efectivos (`2022-06-01` a `2026-09-01`)** × **`364` combinaciones (`2 léxicos × 26 características × 7 ponderaciones`)**.
* **Linaje:** Generado por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R); insumo directo para `06_measures_*`, `07_global_index.rds`, `08_attributions.rds` y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

```r
sento_meas <- readRDS(here::here("data", "processed", "05_sento_measures.rds"))
series_mat <- sento_meas$measures
```

| Slot | Clase / Dimensiones | Contenido y Estructura |
| :--- | :---: | :--- |
| `measures` | `data.table` (`52 × 365`) | Columna `date` (`Date`, `2022-06-01`..`2026-09-01`) + `364` columnas numéricas `<lexicon>--<feature>--<time>`. |
| `features` | `character` (longitud `26`) | Nombres de las 26 variables binarias del corpus. |
| `lexicons` | `character` (longitud `2`) | `c("nrc_es", "crimen_es")`. |
| `time` | `character` (longitud `7`) | `c("linear", "exponential0.2", "exponential0.5", "beta12", "beta13", "beta22", "beta23")`. |
| `sentiment` | `sentiment` / `data.table` | Copia de los puntajes documentales base empleados en la agregación. |
| `stats` | `matrix` (`5 × 364`) | Estadísticos por serie (`mean`, `sd`, `max`, `min`, `meanCorr`). |
| `attribWeights` | `list` (`2`: `W`, `B`) | `W` (`3.916 × 54` `data.table`: `id`, `date` y `52` pesos documentales para atribuciones, con `NA` en cruces inactivos); `B` (`6 × 7` matriz de ponderadores de rezago para los lags `1..6`). |
| `ctr` | `list` (`5`) | Hiperparámetros de control empleados (`within`, `docs`, `time`, `tokens`, `nCore`). |

---

## 6. `06_measures_long.rds` y `06_measures_wide.rds`

* **Rutas relativas:**
  * `data/processed/06_measures_long.rds` (`list` de `2` elementos: `long` `18.928 × 9` y `wide` `52 × 365`)
  * `data/processed/06_measures_wide.rds` (`data.table` de `52 × 365`)
* **Propósito y uso:** Proveen versiones listas para graficación y visualización en formato ordenado (*tidy* largo, `52 meses × 364 series = 18.928` filas) y matriz ancha sin envoltorio S3.
* **Linaje:** Generados por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R). `06_measures_long.rds$long` alimenta el bundle de Shiny (`measures_long`).

> **Nota de consistencia verificada en disco:** `06_measures_long.rds$wide` (`52 × 365`) es idéntico bit a bit a `05_sento_measures.rds$measures` y concuerda con `06_measures_long.rds$long`. En el archivo independiente `06_measures_wide.rds` se observa una ligera diferencia numérica residual (diferencia absoluta máxima `0,0378` en la matriz), por lo que para análisis y tableros el pipeline consume `06_measures_long.rds` o `05_sento_measures.rds`.

```r
measures_bundle <- readRDS(here::here("data", "processed", "06_measures_long.rds"))
measures_long   <- measures_bundle$long
```

### 6.1 Esquema de `06_measures_long.rds$long` (`18.928 × 9`)

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `date` | `Date` | No nula (`0 NA`) | `[2022-06-01, 2026-09-01]` (`52` fechas mensuales) | Mes de la medida agregada. |
| `serie_id` | `character` | No nula (`0 NA`) | `364` identificadores `<lexicon>--<feature>--<time>` | Identificador único compuesto de la serie temporal. |
| `lexicon` | `character` | No nula (`0 NA`) | `"nrc_es"`, `"crimen_es"` (`2` únicos) | Nombre técnico del léxico aplicado. |
| `feature` | `character` | No nula (`0 NA`) | `26` nombres de características (`c_*`, `tema_*`, `loc_*`) | Dimensión territorial o temática de la serie. |
| `time` | `character` | No nula (`0 NA`) | `7` funciones de decaimiento (`linear` .. `beta23`) | Esquema temporal de ponderación aplicado sobre los rezagos. |
| `valor` | `numeric` | No nula (`0 NA`) | `[-1,1438, 0,7660]` | Valor numérico de la medida de sentimiento en el mes `date`. |
| `grupo_feature` | `character` | No nula (`0 NA`) | `"Clúster Territorial"`, `"Tópico / Modalidad DAI"`, `"Localidad"` (`3` únicos) | Agrupación conceptual de `feature` para selectores en Shiny. |
| `feature_label` | `character` | No nula (`0 NA`) | `26` etiquetas legibles en español | Nombre presentable de la característica (ej. `"Clúster: Céntrico e Institucional"`). |
| `lexicon_label` | `character` | No nula (`0 NA`) | `"Léxico General (NRC Español)"`, `"Léxico Seguridad y Crimen Bogotá"` (`2` únicos) | Etiqueta descriptiva del léxico para leyendas de gráficos. |

---

## 7. `07_global_index.rds`

* **Ruta relativa:** `data/processed/07_global_index.rds`
* **Formato / Clase en R:** `list` de `4` elementos
* **Propósito y uso:** Condensa las `364` series temporales en un índice sintético global mensual de tono mediático sobre seguridad en Bogotá (combinando explícitamente las dimensiones de léxicos, características y tiempo con `sento_index(..., do.global = TRUE)`) e identifica meses con picos de alarma o positividad (`peakdates()`).
* **Linaje:** Generado por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R); consumido por [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

```r
idx_global   <- readRDS(here::here("data", "processed", "07_global_index.rds"))
serie_global <- idx_global$serie_global
```

### 7.1 Esquema de `serie_global` (`52 × 7`) y Vectores de Picos

Además de `serie_global`, la lista contiene tres vectores `Date` de longitud `8` cada uno: `peakdates_both`, `peakdates_neg` y `peakdates_pos`.

| Campo en `serie_global` | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `date` | `Date` | No nula (`0 NA`) | `[2022-06-01, 2026-09-01]` (`52` meses) | Fecha mensual de la serie global agregada. |
| `globLex` | `numeric` | No nula (`0 NA`) | `[-0,2496, -0,0187]` | Subíndice agregado a lo largo de la dimensión de léxicos. |
| `globFeat` | `numeric` | No nula (`0 NA`) | `[-0,0192, -0,0014]` | Subíndice agregado a lo largo de las 26 características. |
| `globTime` | `numeric` | No nula (`0 NA`) | `[-0,0713, -0,0053]` | Subíndice agregado a lo largo de las 7 ponderaciones temporales. |
| `global` | `numeric` | No nula (`0 NA`) | `[-0,1134, -0,0085]` | Índice global compuesto del sentimiento mediático distrital por mes. |
| `es_pico` | `logical` | No nula (`0 NA`) | `TRUE` (`8`), `FALSE` (`44`) | Indica si el mes corresponde a una fecha de pico extremo global (`peakdates_both`). |
| `tipo_pico` | `character` | No nula (`0 NA`) | `"Normal"` (`37`), `"Pico de Alarma / Negatividad"` (`8`), `"Pico Positivo / Operatividad"` (`7`) | Clasificación direccional del mes según los vectores `peakdates_neg` y `peakdates_pos`. |

---

## 8. `08_attributions.rds`

* **Ruta relativa:** `data/processed/08_attributions.rds`
* **Formato / Clase en R:** `list` de `8` componentes
* **Propósito y uso:** Contiene el modelo predictivo Elastic Net (`sento_model`) ajustado sobre las `364` series de sentimiento para predecir la tasa mensual distrital de hurto a personas a horizonte `h = 1` mes (`y_tasa_hurto_mensual`, obtenida distribuyendo mensualmente el acumulado anual mediante un patrón estacional mensual del corpus), junto con sus predicciones y atribuciones exactas por documento, rezago, léxico, característica y función de tiempo.
* **Linaje:** Generado por [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R); sus componentes *tidy* y métricas se exportan a `datos_consolidados_shiny.rds` y alimentan el análisis de [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

```r
res_attr <- readRDS(here::here("data", "processed", "08_attributions.rds"))
metricas <- res_attr$metricas_modelo
```

### 8.1 Componentes del Objeto `08_attributions.rds` (`8` slots)

| Slot | Clase / Dimensiones | Descripción |
| :--- | :---: | :--- |
| `modelo` | `sento_model` | Objeto completo de regresión Elastic Net estimado por `sentometrics::sento_model()`. |
| `attributions_raw` | `attributions` (`list` de `5`) | Descomposición en escala de la variable dependiente para `51` meses (`2022-06-01`..`2026-08-01`): `documents` (lista de `51` `data.table` `[id, date, attrib]`), `lags` (`51 × 7`: `lag_0`..`lag_5`), `lexicons` (`51 × 3`), `features` (`51 × 27`) y `time` (`51 × 8`). |
| `attributions_norm` | `attributions` (`list` de `5`) | Misma estructura de `attributions_raw` pero normalizada en el intervalo `[-1, 1]` por periodo. |
| `attr_long_raw` | `data.table` (`1.785 × 5`) | Versión larga ordenada de `features`, `lexicons` y `time` en escala bruta (`51 × 35 componentes`). |
| `attr_long_norm` | `data.table` (`1.785 × 5`) | Versión larga normalizada (`[-0,9999, 0,9917]`). |
| `ajuste_temporal` | `tbl_df` (`51 × 4`) | Serie de ajuste entre valores observados y predichos en el horizonte objetivo `2022-07-01`..`2026-09-01`. |
| `coeficientes` | `tbl_df` (`46 × 2`) | Los `46` predictores activos seleccionados por Elastic Net (`β ≠ 0`), ordenados por `abs(coeficiente)`. |
| `metricas_modelo` | `list` (`9` escalares) | Parámetros e indicadores de bondad de ajuste del modelo final. |

### 8.2 Campos de las Tablas Ordenadas (`attr_long_*`, `ajuste_temporal`, `coeficientes` y `metricas_modelo`)

| Tabla | Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `attr_long_raw` / `attr_long_norm` (`1.785 × 5`) | `date` | `Date` | `0 NA` | `[2022-06-01, 2026-08-01]` (`51` meses de origen) | Fecha del predictor cuya contribución se evalúa en `h = 1`. |
| | `componente` | `character` | `0 NA` | `35` componentes (`26` features + `2` lexicons + `7` times) | Identificador del predictor o dimensión agrupada. |
| | `atribucion` | `numeric` | `0 NA` | Bruta: `[-140,5713, 58,3281]`; Norm.: `[-0,9999, 0,9917]` | Contribución atribuida al valor predicho de la tasa de hurto. |
| | `dimension` | `character` | `0 NA` | `"features"` (`1.326`), `"time"` (`357`), `"lexicons"` (`102`) | Eje de descomposición al que pertenece `componente`. |
| | `componente_label` | `character` | `0 NA` | `35` etiquetas legibles en español | Nombre formateado para ejes y tarjetas de gráficos. |
| `ajuste_temporal` (`51 × 4`) | `date` | `Date` | `0 NA` | `[2022-07-01, 2026-09-01]` (`51` meses objetivo) | Mes de realización de la tasa de hurto predicha (`t + 1`). |
| | `observado` | `numeric` | `0 NA` | `[29,95, 321,28]` | Tasa mensual distrital observada de hurto a personas (`y_tasa_hurto_mensual`). |
| | `predicho` | `numeric` | `0 NA` | `[64,33, 266,15]` | Valor predicho dentro de muestra por el modelo Elastic Net (`α = 0,2`). |
| | `residual` | `numeric` | `0 NA` | `[-52,98, 55,13]` | Error de predicción (`observado - predicho`). |
| `coeficientes` (`46 × 2`) | `variable` | `character` | `0 NA` | `46` series activas `<lexicon>--<feature>--<time>` | Nombre completo de cada variable predictora con coeficiente distinto de cero. |
| | `coeficiente` | `numeric` | `0 NA` | `[-40,3039, 55,4846]` | Coeficiente estimado en la solución regularizada final. |

**Parámetros verificados en `metricas_modelo`:** `alpha_optimo = 0,2`, `lambda_optimo = 13,46494`, `horizonte_h = 1`, `criterio = "BIC"`, `r2_in_sample = 0,8753`, `rmse = 21,593`, `n_observaciones = 51`, `n_predictores = 364`, `n_activos = 46`.

---

## 9. `datos_consolidados_shiny.rds`

* **Ruta relativa:** `data/processed/datos_consolidados_shiny.rds`
* **Formato / Clase en R:** `list` autocontenida de `12` componentes
* **Propósito y uso:** Empaqueta en un único artefacto ligero todas las tablas, geometrías simplificadas y salidas analíticas necesarias para que el tablero interactivo [`app/app.R`](../../app/app.R) arranque de forma autónoma y rápida sin cargar ni objetos pesados de `sentometrics` (`modelo`, `attributions_raw`, `05_sento_measures.rds`) ni el GeoJSON sin simplificar.
* **Linaje:**
  * **Generado por:** [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) (combinando `panel_consolidado_localidad_anual.parquet`, `clusters_localidades_kmeans.parquet`, `localidades_bogota_raw.geojson` simplificado con `dTolerance = 0.0005` en `EPSG:4326`, `01_sento_corpus.rds`, `02_lexicons_es.rds`, `04_peak_docs.rds`, `06_measures_long.rds`, `07_global_index.rds` y las tablas *tidy* de `08_attributions.rds`).
  * **Consumido por:** [`app/app.R`](../../app/app.R) (único archivo de datos cargado al inicio de la aplicación).

```r
shiny_bundle <- readRDS(here::here("data", "processed", "datos_consolidados_shiny.rds"))
names(shiny_bundle)
```

### 9.1 Inventario de los 12 Componentes y Uso por Pestaña en Shiny

| Slot | Clase / Dimensiones | Origen exacto | Consumo en [`app/app.R`](../../app/app.R) |
| :--- | :---: | :--- | :--- |
| `panel_localidades` | `tbl_df` (`95 × 24`) | `panel_consolidado_localidad_anual` (`20` cols) + `cluster_id`, `cluster_nombre`, `perfil_seguridad`, `silueta_localidad` | Carga global y pestañas **1 (Panorama)**, **2 (Mi localidad)**, **3 (Hurto vs. prensa)** y **4 (Clusters)** para mapas, KPIs, rankings y correlaciones. |
| `clusters_perfiles` | `tbl_df` (`19 × 11`) | `clusters_localidades_kmeans.parquet` | Cargado al inicio del servidor (`clusters_perfiles`); la información territorial se consulta también vía `panel_localidades` y `geometrias`. |
| `geometrias` | `sf` (`19 × 13`, `WGS 84`) | `localidades_bogota_raw.geojson` (`CMIULOCAL`, `CMNOMLOCAL` como `nombre_oficial`) unido a `clusters_localidades_kmeans` + `geometry` simplificada | Polígonos base de los mapas Leaflet en **1 (Panorama)** y **4 (Clusters)**. |
| `corpus_stats_mes` | `tbl_df` (`57 × 32`) | `sentometrics::corpus_summarize(corpus, by = "month")$stats` (`date` `2022-01-01`..`2026-09-01`, `documents` `16..166`, `totalTokens`, `meanTokens` `52,02..134,93`, `minTokens`, `maxTokens` + `26` features) | Cargado al inicio del servidor; la pestaña **6 (Datos y método)** resume estadísticas derivadas directamente del corpus documental. |
| `corpus_stats_anio` | `tbl_df` (`5 × 32`) | `sentometrics::corpus_summarize(corpus, by = "year")$stats` (`documents` `448..1.070`, `totalTokens` `41.079..114.870`, etc.) | Cargado al inicio del servidor junto con `corpus_stats_mes`. |
| `lexicos_info` | `list` (`4`) | `02_lexicons_es.rds`: `nrc_es` (`4.388 × 2`), `crimen_es` (`105 × 2`), `valence_shifters` (`30 × 3`), `comparacion_metodo` (`list` de `4`) | Cargado al inicio del servidor como referencia metodológica de los léxicos. |
| `peak_docs` | `list` (`5`) | `04_peak_docs.rds` (`peak_ids_*`, `tabla_completa` `3.916 × 21`, `top_criticas` `229 × 21`) | `tabla_completa` alimenta el filtro de noticias en **2 (Mi localidad)** y la tabla exploratoria DT en **6 (Datos y método)**. |
| `measures_long` | `tbl_df` (`18.928 × 9`) | `06_measures_long.rds$long` | Selector dinámico de series mensuales (`nrc_es` / `crimen_es`, características y ponderaciones) en **5 (Sentometrics y Elastic Net)**. |
| `global_index` | `list` (`4`) | `07_global_index.rds` (`serie_global` `52 × 7` y `peakdates_*` de longitud `8`) | `peakdates_neg` marca fechas críticas sobre el gráfico temporal de **5 (Sentometrics y Elastic Net)**; `serie_global` queda disponible en carga global. |
| `attributions` | `list` (`5`) | Subconjunto *tidy* de `08_attributions.rds`: `attr_long_raw`, `attr_long_norm`, `ajuste_temporal`, `coeficientes`, `metricas_modelo` | Pestaña **5 (Sentometrics y Elastic Net)**: métricas del modelo, serie observado vs. predicho (`ajuste_temporal`), coeficientes activos y contribuciones (`attr_long_raw` / `attr_long_norm`). |
| `fecha_generacion` | `POSIXct` (`1`) | `Sys.time()` al exportar (`"2026-11-11 20:15:19 -05"`) | Marca temporal de trazabilidad de la última compilación del bundle. |
| `horizonte` | `character` (`1`) | `"2022-2026"` | Constante descriptiva de la ventana temporal del análisis. |

---

* **Siguiente documento:** [`04_tablas_salida.md`](./04_tablas_salida.md) — Tablas exportadas en `output/tables/*.csv`.
