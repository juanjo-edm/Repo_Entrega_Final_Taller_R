# Capa 2: Diccionario de Tablas Procesadas (`data/processed/*.parquet`)

Esta capa almacena los cinco conjuntos de datos tabulares limpios, cruzados y enriquecidos en formato **Apache Parquet**, abarcando las **19 localidades urbanas** de Bogotá D.C. en el periodo **2022–2026**.

* **Capa anterior:** [`01_datos_crudos.md`](./01_datos_crudos.md)
* **Índice del diccionario:** [`README.md`](./README.md)
* **Siguiente capa:** [`03_artefactos_sentometrics_shiny.md`](./03_artefactos_sentometrics_shiny.md)

---

## Tabla de Contenido

1. [`delitos_localidad_mensual.parquet`](#1-delitos_localidad_mensualparquet) — Conteos mensuales oficiales SIEDCO por localidad y mes (`1.083 × 8`)
2. [`panel_delitos_poblacion_mensual.parquet`](#2-panel_delitos_poblacion_mensualparquet) — Panel mensual de delitos, población y tasas por 100.000 hab. (`1.083 × 13`)
3. [`noticias_procesadas.parquet`](#3-noticias_procesadasparquet) — Microdatos del corpus de prensa limpios, clasificados y calificados (`3.916 × 42`)
4. [`clusters_localidades_kmeans.parquet`](#4-clusters_localidades_kmeansparquet) — Tipología territorial $K$-means por perfiles de hurto (`19 × 11`)
5. [`panel_consolidado_localidad_anual.parquet`](#5-panel_consolidado_localidad_anualparquet) — Panel maestro criminalidad–demografía–sentimiento objetivo (`95 × 20`)

---

## 1. `delitos_localidad_mensual.parquet`

* **Ruta relativa:** `data/processed/01_delitos/delitos_localidad_mensual.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `1.083` filas × `8` columnas (`19 localidades × 57 meses`, enero de `2022` a septiembre de `2026`)
* **Unidad de observación (grano):** Combinación `Localidad × Mes` (`fecha_mes`).
* **Llave primaria compuesta (`PK`):** `(codigo_localidad, fecha_mes)`
* **Llaves foráneas / de cruce (`FK`):** `codigo_localidad` vincula con [`SIEDCO.csv`](./01_datos_crudos.md#1-siedcocsv) (`COD_LOCALIDAD`), [`localidades_bogota_raw.geojson`](./01_datos_crudos.md#2-localidades_bogota_rawgeojson) (`CMIULOCAL`) y [`poblacion_localidades_raw.parquet`](./01_datos_crudos.md#3-poblacion_localidades_rawparquet) (`CODIGO_LOCALIDAD`).
* **Propósito y uso:** Consolida los microdatos mensuales de las tres modalidades de hurto objetivo (`HURTO A PERSONAS`, `HURTO A RESIDENCIAS`, `HURTO MOTOCICLETAS`) desde `SIEDCO.csv` en una malla temporal balanceada de 57 meses, normalizando tildes y completando ceros explícitos cuando una celda no registra casos.
* **Linaje:**
  * **Generado por:** [`scripts/02_procesamiento/01_delitos/procesamiento_delitos.R`](../../scripts/02_procesamiento/01_delitos/procesamiento_delitos.R) (a partir de `SIEDCO.csv`).
  * **Consumido por:** [`scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R`](../../scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R).
* **Controles de auditoría:** Exclusión explícita de Sumapaz (`20`) y Sin Localización (`99`); `stopifnot()` verifica exactamente `1.083` filas, `19` localidades únicas, rango `2022-01-01`..`2026-09-01` y ausencia de valores `NA`.

```r
delitos_mensual <- arrow::read_parquet(
  here::here("data", "processed", "01_delitos", "delitos_localidad_mensual.parquet")
)
```

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | `sprintf("%02d", COD_LOCALIDAD)` (`SIEDCO.csv`) | Código oficial DANE/Distrito a dos dígitos para las 19 localidades urbanas. |
| `localidad` | `character` | No nula (`0 NA`) | `"Usaquén"`, `"La Candelaria"`, ..., `"Ciudad Bolívar"` (`19` únicos) | `LOCALIDAD` homologado (`"Candelaria"` → `"La Candelaria"`) | Nombre oficial estandarizado con tildes de la localidad. |
| `año` | `integer` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | `ANIO` (`SIEDCO.csv`) | Año del registro mensual. |
| `mes` | `integer` | No nula (`0 NA`) | `[1, 12]` (`12` únicos; hasta `9` en `2026`) | `MES` (`SIEDCO.csv`) | Mes calendario del registro mensual. |
| `fecha_mes` | `Date` | No nula (`0 NA`) | `[2022-01-01, 2026-09-01]` (`57` únicos) | Primer día de `(año, mes)` | Llave temporal mensual exacta. |
| `hurto_personas` | `integer` | No nula (`0 NA`) | `[53, 2.179]` (`697` únicos) | Suma mensual de `CANTIDAD` (`HURTO A PERSONAS`) | Conteo mensual oficial de hurtos a personas. |
| `hurto_residencias` | `integer` | No nula (`0 NA`) | `[0, 178]` (`108` únicos) | Suma mensual de `CANTIDAD` (`HURTO A RESIDENCIAS`) | Conteo mensual oficial de hurtos a residencias. |
| `hurto_motos` | `integer` | No nula (`0 NA`) | `[0, 118]` (`94` únicos) | Suma mensual de `CANTIDAD` (`HURTO MOTOCICLETAS`) | Conteo mensual oficial de hurtos a motocicletas. |

---

## 2. `panel_delitos_poblacion_mensual.parquet`

* **Ruta relativa:** `data/processed/02_poblacion/panel_delitos_poblacion_mensual.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `1.083` filas × `13` columnas (`19 localidades × 57 meses`)
* **Unidad de observación (grano):** Combinación `Localidad × Mes` (`fecha_mes`).
* **Llave primaria compuesta (`PK`):** `(codigo_localidad, fecha_mes)`
* **Propósito y uso:** Integra los conteos mensuales oficiales de `SIEDCO.csv` con la población anual proyectada por la Secretaría de Salud para calcular tasas mensuales por cada `100.000` habitantes. Provee simultáneamente las tasas mensualizadas para la variable dependiente real de Elastic Net (`h = 1`) y las tasas anualizadas base para $K$-means y análisis territorial.
* **Linaje:**
  * **Generado por:** [`scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R`](../../scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R) (cruce de `delitos_localidad_mensual.parquet` con `poblacion_localidades_raw.parquet` filtrando `CODIGO_LOCALIDAD != 0`).
  * **Consumido por:**
    * [`scripts/04_clustering_kmeans.R`](../../scripts/04_clustering_kmeans.R) (agregado anual promedio 2022–2026 para clustering).
    * [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) (variable objetivo mensual real de Elastic Net y agregación al panel consolidado anual).
    * [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).
* **Controles de auditoría:** Verifica unión completa sin pérdida de filas (`1.083` registros) y población estrictamente positiva en todos los pares `(codigo_localidad, fecha_mes)`.

```r
panel_delitos_mensual <- arrow::read_parquet(
  here::here("data", "processed", "02_poblacion", "panel_delitos_poblacion_mensual.parquet")
)
```

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Heredado de `delitos_localidad_mensual` | Código identificador oficial de la localidad urbana. |
| `localidad` | `character` | No nula (`0 NA`) | `"Usaquén"`, ..., `"Ciudad Bolívar"` (`19` únicos) | Heredado de `delitos_localidad_mensual` | Nombre homologado de la localidad. |
| `año` | `integer` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | Heredado de `delitos_localidad_mensual` | Año de análisis (`2022`–`2026`). |
| `mes` | `integer` | No nula (`0 NA`) | `[1, 12]` (`12` únicos) | Heredado de `delitos_localidad_mensual` | Mes calendario (`1`–`12`; hasta `9` en `2026`). |
| `fecha_mes` | `Date` | No nula (`0 NA`) | `[2022-01-01, 2026-09-01]` (`57` únicos) | Heredado de `delitos_localidad_mensual` | Fecha primer día del mes. |
| `hurto_personas` | `integer` | No nula (`0 NA`) | `[53, 2.179]` | Heredado de `delitos_localidad_mensual` | Conteo mensual de hurtos a personas. |
| `hurto_residencias` | `integer` | No nula (`0 NA`) | `[0, 178]` | Heredado de `delitos_localidad_mensual` | Conteo mensual de hurtos a residencias. |
| `hurto_motos` | `integer` | No nula (`0 NA`) | `[0, 118]` | Heredado de `delitos_localidad_mensual` | Conteo mensual de hurtos a motocicletas. |
| `poblacion` | `numeric` | No nula (`0 NA`) | `[16.449, 1.252.218]` | $\sum_{\text{sexo, edad}} \text{POBLACION}$ por `(CODIGO_LOCALIDAD, ANO)` | Proyección oficial total de habitantes de la localidad en el año correspondiente. |
| `tasa_hurto_personas` | `numeric` | No nula (`0 NA`) | `[24,05, 2.889,81]` | `round((hurto_personas / poblacion) * 100000, 2)` | Tasa mensual de hurto a personas por cada 100.000 habitantes. |
| `tasa_hurto_residencias` | `numeric` | No nula (`0 NA`) | `[0, 63,76]` | `round((hurto_residencias / poblacion) * 100000, 2)` | Tasa mensual de hurto a residencias por cada 100.000 habitantes. |
| `tasa_hurto_motos` | `numeric` | No nula (`0 NA`) | `[0, 37,13]` | `round((hurto_motos / poblacion) * 100000, 2)` | Tasa mensual de hurto a motocicletas por cada 100.000 habitantes. |
| `tasa_hurto_total` | `numeric` | No nula (`0 NA`) | `[33,32, 2.942,85]` | `round(((hurto_personas + hurto_residencias + hurto_motos) / poblacion) * 100000, 2)` | Tasa mensual agregada de las tres modalidades por cada 100.000 habitantes. |

---

## 3. `noticias_procesadas.parquet`

* **Ruta relativa:** `data/processed/03_noticias/noticias_procesadas.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `3.916` filas × `42` columnas (`993` filas marcadas con `es_objetivo_3mod == TRUE`)
* **Unidad de observación (grano):** Artículo periodístico individual único (`doc_1` a `doc_3916`, ordenado cronológicamente por `localidad` y `fecha`).
* **Llave primaria (`PK`):** `id` (y unicidad funcional en `enlace` y `titulo`).
* **Llaves foráneas / de cruce (`FK`):**
  * Los `993` artículos donde `es_objetivo_3mod == TRUE` enlazan vía `id` con `sentometrics_pipeline.rds` (`corpus_sento`, `sentiment_scores`, `peak_docs`, `sento_measures$attribWeights$W`).
  * `localidad` y `año` enlazan con `panel_consolidado_localidad_anual.parquet`.
  * `cluster_id` enlaza con `clusters_localidades_kmeans.parquet`.
* **Propósito y uso:** Constituye la tabla maestra a nivel de documento del proyecto. Primero [`procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R) limpia HTML/cookies/anuncios, añade métricas de longitud y clasifica jerárquicamente la taxonomía DAI (`32` columnas iniciales). Después [`03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) agrega la bandera `es_objetivo_3mod` (`TRUE` para las `993` notas de las 3 modalidades SIEDCO comparables), los puntajes auxiliares de sentimiento para las `3.916` noticias recopiladas y la pertenencia al clúster territorial (`42` columnas finales).
* **Linaje:**
  * **Generado por:** [`scripts/02_procesamiento/03_noticias/procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R) (escritura inicial) y [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) (enriquecimiento y escritura final).
  * **Consumido por:** [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R), [`scripts/06_descriptivos_corpus.R`](../../scripts/06_descriptivos_corpus.R), [`output/entregas/01_primera_entrega/01_entrega_1_propuesta_eda.qmd`](../../output/entregas/01_primera_entrega/01_entrega_1_propuesta_eda.qmd) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).
* **Controles de auditoría:** Conserva los `3.916` registros originales (`sum(es_objetivo_3mod) == 993`), verifica alineación exacta con `sentometrics_pipeline.rds$corpus_sento` para el subconjunto objetivo y ausencia de `NA` salvo en `confianza_dai` (`790` casos `"No DAI"`) y `motivo_exclusion` (`3.126` casos `es_dai_amplio == TRUE`).

```r
noticias_proc <- arrow::read_parquet(
  here::here("data", "processed", "03_noticias", "noticias_procesadas.parquet")
)
```

### 3.1 Identificación Temporal, Geográfica y Banderas de Ventana (14 campos)

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `id` | `character` | No nula (`0 NA`) | `"doc_1"` .. `"doc_3916"` (`3.916` únicos) | `paste0("doc_", row_number())` en `03_analisis_sentometrics.R` tras ordenar por `(localidad, fecha)` | Identificador único determinista usado como llave primaria en `sentometrics`. |
| `fecha` | `Date` | No nula (`0 NA`) | `[2022-01-01, 2026-09-30]` (`527` únicos) | Heredado de tabla cruda | Fecha de publicación de la noticia. |
| `año` | `integer` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | `lubridate::year(fecha)` (en crudo) | Año calendario de publicación. |
| `mes` | `integer` | No nula (`0 NA`) | `[1, 12]` (`12` únicos) | `lubridate::month(fecha)` (en crudo) | Mes numérico de publicación (`1`–`12`). |
| `año_mes` | `character` | No nula (`0 NA`) | `"2022-01"` .. `"2026-09"` (`57` únicos) | `format(fecha, "%Y-%m")` (en crudo) | Llave mensual de agregación temporal para series `sentometrics`. |
| `trimestre` | `character` | No nula (`0 NA`) | `"2022-Q1"` .. `"2026-Q3"` (`19` únicos) | Derivado de `fecha` (en crudo) | Trimestre calendario de publicación. |
| `semana_año` | `integer` | No nula (`0 NA`) | `[1, 52]` (`52` únicos) | Derivado de `fecha` (en crudo) | Semana epidemiológica/calendario dentro del año. |
| `fecha_imputada` | `logical` | No nula (`0 NA`) | `TRUE` / `FALSE` | `lubridate::day(fecha) == 1L` | Bandera de auditoría que marca registros con fecha día `01` (imputada o coincidente con inicio de mes). |
| `ventana_ene_sep` | `logical` | No nula (`0 NA`) | `TRUE` / `FALSE` | `mes <= 9L` | Indica si la noticia cae en la ventana enero–septiembre comparable con los cortes oficiales SDSCJ. |
| `localidad` | `character` | No nula (`0 NA`) | `"Antonio Nariño"`, ..., `"Usme"` (`19` únicos) | Heredado de tabla cruda | Nombre oficial normalizado de la localidad urbana asignada. |
| `localidad_slug` | `character` | No nula (`0 NA`) | `"antonio_narino"`, ..., `"candelaria"`, ..., `"usme"` (`19` únicos) | Normalizado minúsculas sin tildes en `procesamiento_noticias.R` (`"La Candelaria"` → `"candelaria"`) | Slug territorial empleado en cruces internos de procesamiento de texto. |
| `confianza_geografica` | `character` | No nula (`0 NA`) | `"Media"` (`3.384`), `"Alta"` (`532`) | Heredado de tabla cruda | Nivel de certeza en la vinculación de la nota con la localidad asignada. |
| `menciona_localidad` | `logical` | No nula (`0 NA`) | `TRUE` / `FALSE` | Búsqueda regex del topónimo en `texto_completo_nlp` | Verifica explícitamente si el texto limpio menciona el nombre de la localidad asignada. |
| `enlace` | `character` | No nula (`0 NA`) | URLs únicas (`3.916` únicos) | Heredado de tabla cruda | URL original resuelta del artículo periodístico. |

### 3.2 Fuente, Contenido Textual y Métricas Volumétricas (10 campos)

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `fuente` | `character` | No nula (`0 NA`) | `138` dominios/medios únicos (ej. `"bogota.gov.co"`, `"www.infobae.com"`) | Heredado de tabla cruda | Medio o dominio web emisor de la noticia. |
| `tipo_medio` | `character` | No nula (`0 NA`) | `"Institucional"` (`1.532`), `"Prensa Digital General"` (`875`), `"Nativo Digital"` (`874`), `"Prensa Tradicional"` (`449`), `"Television y Radio"` (`149`), `"Prensa Local y Comunitaria"` (`37`) | Heredado de tabla cruda | Taxonomía de seis categorías del tipo de medio de comunicación. |
| `titulo` | `character` | No nula (`0 NA`) | Texto libre (`3.916` únicos) | Heredado de tabla cruda | Titular de la noticia. |
| `resumen` | `character` | No nula (`0 NA`) | Texto libre (`3.838` únicos) | Heredado de tabla cruda | Extracto o entradilla de Google News RSS. |
| `cuerpo` | `character` | No nula (`0 NA`) | Texto limpio (`3.904` únicos) | `cuerpo` crudo tras depurar HTML, avisos de cookies y bloques publicitarios | Cuerpo principal del artículo después de la limpieza textual. |
| `texto_completo_nlp` | `character` | No nula (`0 NA`) | Texto limpio concatenado (`3.916` únicos) | `str_squish(paste(titulo, resumen, cuerpo))` | Campo textual unificado base para las clasificaciones temáticas y extracción NLP. |
| `caracteres_cuerpo` | `integer` | No nula (`0 NA`) | `[40, 25.489]` (`1.396` únicos) | `nchar(cuerpo)` | Número total de caracteres del campo `cuerpo` limpio. |
| `palabras_cuerpo` | `integer` | No nula (`0 NA`) | `[7, 4.298]` (`750` únicos) | `stringr::str_count(cuerpo, "\\S+")` | Conteo aproximado de palabras (tokens separados por espacios) en `cuerpo`. |
| `palabras_titulo` | `integer` | No nula (`0 NA`) | `[3, 33]` (`30` únicos) | `stringr::str_count(titulo, "\\S+")` | Número de palabras en `titulo`. |
| `texto_corto` | `logical` | No nula (`0 NA`) | `TRUE` / `FALSE` | `palabras_cuerpo < 30L` | Bandera de control para notas breves cuyo cuerpo contiene menos de 30 palabras. |

### 3.3 Taxonomía y Clasificación Jerárquica DAI / SDSCJ (9 campos)

La clasificación del delito sigue una evaluación jerárquica estricta en orden de precedencia `titulo` → `resumen` → `cuerpo`, separando las categorías oficiales DAI de las notas de contexto no delictivo (`nodai_*`).

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `delito_alto_impacto` | `character` | No nula (`0 NA`) | `15` etiquetas originales de scraping | Heredado de tabla cruda | Categoría temática con la que fue consultada/capturada la noticia en Google News. |
| `tipo_delito_dominante` | `character` | No nula (`0 NA`) | `15` etiquetas originales | Heredado de tabla cruda | Subtipo delictivo principal detectado durante la etapa de scraping. |
| `modalidad_dai` | `character` | No nula (`0 NA`) | `20` modalidades: `hurto_automotores` (`576`), `hurto_no_identificado` (`538`), `hurto_personas` (`519`), `homicidio` (`453`), `hurto_comercio` (`350`), `nodai_sin_hecho_delictivo` (`307`), `nodai_operatividad` (`183`), `hurto_celulares` (`143`), `hurto_residencias` (`141`), `hurto_motocicletas` (`116`), `nodai_politica_seguridad` (`103`), `lesiones_personales` (`81`), `nodai_microtrafico` (`78`), `hurto_bicicletas` (`74`), `extorsion` (`69`), `nodai_otros_hurtos` (`65`), `nodai_otros_delitos` (`54`), `delitos_sexuales` (`33`), `violencia_intrafamiliar` (`17`), `hurto_entidades_financieras` (`16`) | Reglas regex jerárquicas en `procesamiento_noticias.R` | Clasificación granular en 20 categorías (modalidades de hurto, otros DAI y exclusiones No DAI). |
| `campo_clasificacion` | `character` | No nula (`0 NA`) | `"titulo"`, `"resumen"`, `"cuerpo"` (`3` únicos) | Primer campo donde hizo coincidencia la regla regex | Indica el nivel textual que determinó la clasificación de `modalidad_dai`. |
| `delito_sdscj` | `character` | No nula (`0 NA`) | `13` clases: `No DAI` (`790`), `Hurto a personas` (`736`), `Hurto de automotores` (`576`), `Hurto (modalidad no identificada)` (`538`), `Homicidio` (`453`), `Hurto a comercio` (`350`), `Hurto a residencias` (`141`), `Hurto de motocicletas` (`116`), `Lesiones personales` (`81`), `Extorsión` (`69`), `Delitos sexuales` (`33`), `Violencia intrafamiliar` (`17`), `Hurto a entidades financieras` (`16`) | Homologación de `modalidad_dai` (agrupa `hurto_celulares` y `hurto_bicicletas` dentro de `Hurto a personas`) | Categoría oficial homologada con la nomenclatura de la SDSCJ; las 6 modalidades `nodai_*` se consolidan en `"No DAI"`. |
| `confianza_dai` | `character` | Admite `NA` (`790 NA`) | `"Alta"` (`2.470`), `"Baja"` (`410`), `"Media"` (`246`), `<NA>` (`790`) | Derivado de `campo_clasificacion` y `es_dai_amplio` (`NA` si `"No DAI"`) | Certeza de la asignación DAI según el campo de coincidencia (`titulo` → Alta, `resumen` → Media, `cuerpo` → Baja). |
| `es_dai_estricto` | `logical` | No nula (`0 NA`) | `TRUE` / `FALSE` | `delito_sdscj != "No DAI" & delito_sdscj != "Hurto (modalidad no identificada)"` | Indica si el artículo corresponde inequívocamente a una categoría DAI oficial específica. |
| `es_dai_amplio` | `logical` | No nula (`0 NA`) | `TRUE` (`3.126`) / `FALSE` (`790`) | `delito_sdscj != "No DAI"` | Incluye las noticias DAI estrictas más las notas de `"Hurto (modalidad no identificada)"`. |
| `motivo_exclusion` | `character` | Admite `NA` (`3.126 NA`) | `"sin_hecho_delictivo"` (`307`), `"operatividad"` (`183`), `"politica_seguridad"` (`103`), `"microtrafico"` (`78`), `"otros_hurtos"` (`65`), `"otros_delitos"` (`54`), `<NA>` (`3.126`) | Extraído de `modalidad_dai` cuando `es_dai_amplio == FALSE` | Causa de exclusión del marco DAI oficial para las `790` noticias etiquetadas `"No DAI"`. |

### 3.4 Enriquecimiento Léxico (`sentometrics`) y Tipología Territorial (10 campos)

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `es_objetivo_3mod` | `logical` | No nula (`0 NA`) | `TRUE` (`993`) / `FALSE` (`2.923`) | `delito_sdscj %in% c("Hurto a personas", "Hurto a residencias", "Hurto de motocicletas")` | Indica si el artículo pertenece a las 3 modalidades SIEDCO comparables modeladas en `sentometrics`. |
| `word_count` | `numeric` | No nula (`0 NA`) | `[21, 197]` | Calculado por `sentometrics::compute_sentiment()` | Conteo de tokens en el texto resumido (`titulo` + `resumen` + primeros `800` caracteres de `cuerpo`). |
| `score_nrc_es` | `numeric` | No nula (`0 NA`) | `[-1,25, 1,4]` | `proportionalPol` con léxico `nrc_es` + valencia | Polaridad del documento según el léxico general español NRC ajustado por modificadores de valencia. |
| `score_crimen_es` | `numeric` | No nula (`0 NA`) | `[-1,3, 0,8]` | `proportionalPol` con léxico `crimen_es` + valencia | Polaridad del documento según el léxico especializado de criminalidad en Bogotá (`crimen_es`). |
| `sentimiento_score` | `numeric` | No nula (`0 NA`) | `[-1, 0,9]` | `round(0.5 * score_nrc_es + 0.5 * score_crimen_es, 4)` | Índice compuesto de sentimiento documental en escala continua; valores negativos expresan tono de alarma/inseguridad. |
| `sentimiento_categoria` | `character` | No nula (`0 NA`) | `"Negativo"` (`2.604`), `"Positivo"` (`1.114`), `"Neutro"` (`198`) | Negativo `< -0.02`; Neutro `[-0.02, 0.02]`; Positivo `> 0.02` | Clasificación discreta de la polaridad basada en `sentimiento_score`. |
| `cluster_id` | `integer` | No nula (`0 NA`) | `1`, `2`, `3` (`3` únicos) | Unión por `localidad` desde `clusters_localidades_kmeans.parquet` | Identificador numérico del clúster territorial asignado a la localidad de la noticia. |
| `cluster_nombre` | `character` | No nula (`0 NA`) | `"Céntrico e Institucional"`, `"Comercial y Automotor"`, `"Residencial y Periférico"` (`3` únicos) | Unión desde `clusters_localidades_kmeans.parquet` | Nombre descriptivo del clúster territorial. |
| `perfil_seguridad` | `character` | No nula (`0 NA`) | 3 perfiles descriptivos por clúster | Unión desde `clusters_localidades_kmeans.parquet` | Síntesis criminológica del perfil de seguridad del clúster territorial correspondiente. |

---

## 4. `clusters_localidades_kmeans.parquet`

* **Ruta relativa:** `data/processed/clusters_localidades_kmeans.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `19` filas × `11` columnas
* **Unidad de observación (grano):** Localidad urbana individual de Bogotá D.C. (`19` localidades).
* **Llave primaria (`PK`):** `codigo_localidad` (y unicidad biunívoca en `localidad`).
* **Propósito y uso:** Almacena la tipología espacial no supervisada obtenida mediante $K$-means sobre las tasas promedio anualizadas de `SIEDCO.csv` (estandarizadas $Z$-score) de hurto a personas, residencias y motocicletas en el periodo 2022–septiembre de 2026. Evaluando $K \in \{2, \dots, 6\}$, el algoritmo selecciona **$K^* = 3$** con silueta promedio global de **`0,5211`** y cero siluetas negativas (partición `13 / 5 / 1`):
  * **Clúster 1 — `Céntrico e Institucional`** (`5` localidades): *La Candelaria, Chapinero, Santa Fe, Teusaquillo, Barrios Unidos*.
  * **Clúster 2 — `Comercial y Automotor`** (`1` localidad): *Los Mártires*.
  * **Clúster 3 — `Residencial y Periférico`** (`13` localidades): *Antonio Nariño, Puente Aranda, Fontibón, Engativá, Usaquén, Tunjuelito, Kennedy, Rafael Uribe Uribe, Suba, San Cristóbal, Ciudad Bolívar, Bosa, Usme*.
* **Por qué se agrupan tasas anuales y no mensuales:** (1) la tipología asigna una etiqueta fija por localidad (`19` territorios) como covariable de `sentometrics` y cartografía, evitando que `10` de `19` localidades cambien de clúster mes a mes por estacionalidad o meses en cero (`20` en motos y `4` en residencias); (2) coincide con el denominador anual de población (SDS), la escala criminológica estándar (`3.069,9`, `112,4` y `73,5` anuales frente a `269,3`, `9,9` y `6,4` mensuales) y la estabilidad intertemporal (`13 / 5 / 1` excluyendo `2026` o `2022`); y (3) bajo `Z-score`, promediar los `57` meses entrega correlaciones iguales a `1,0000`, silueta `0,5211` y $\text{ARI} = 1{,}0000$, dejando el panel mensual completo para Elastic Net ($N = 51$).
* **Por qué se elige `Z-score`:** aunque `Min-Max [0, 1]` (`0,5614`) y `PCA 2D` (`0,5539`, `96,89 %` de varianza en `PC1 + PC2`) muestran siluetas más altas porque la métrica se calcula dentro de su propio espacio transformado, las tres recetas producen exactamente la misma partición ($\text{ARI} = 1{,}0000$, `0` siluetas negativas). Se conserva `Z-score` para mantener interpretación directa en desviaciones estándar sobre las tres tasas sin depender de extremos muestrales (`Min-Max`) ni perder el `3,11 %` de `PC3` (`PCA 2D`), frente a `Robusto (Mediana / IQR)` (`0,4562`, `1` negativa, $\text{ARI} = 0{,}8484$) y `Log(1 + x) + Z-score` (`0,4442`, $\text{ARI} = 0{,}3380$).
* **Linaje:**
  * **Generado por:** [`scripts/04_clustering_kmeans.R`](../../scripts/04_clustering_kmeans.R) (usando semilla fija `set.seed(2026)`, `nstart = 50`).
  * **Consumido por:** [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R), [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd). También se exporta de forma idéntica a [`output/tables/tabla_clustering_kmeans_perfiles.csv`](./04_tablas_salida.md#1-tabla_clustering_kmeans_perfilescsv).

```r
clusters_km <- arrow::read_parquet(
  here::here("data", "processed", "clusters_localidades_kmeans.parquet")
)
```

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Heredado de `panel_delitos_poblacion_mensual` | Código identificador oficial de la localidad. |
| `localidad` | `character` | No nula (`0 NA`) | `19` nombres oficiales | Heredado de `panel_delitos_poblacion_mensual` | Nombre oficial normalizado de la localidad. |
| `tasa_personas_prom` | `numeric` | No nula (`0 NA`) | `[645,304, 9.337,386]` (`19` únicos) | `mean(tasa_hurto_personas anual)` 2022–2026 (variable usada en $K$-means) | Tasa promedio quinquenal de hurto a personas por 100.000 hab. |
| `tasa_resid_prom` | `numeric` | No nula (`0 NA`) | `[44,506, 219,660]` (`19` únicos) | `mean(tasa_hurto_residencias anual)` 2022–2026 (variable usada en $K$-means) | Tasa promedio quinquenal de hurto a residencias por 100.000 hab. |
| `tasa_motos_prom` | `numeric` | No nula (`0 NA`) | `[19,034, 187,432]` (`19` únicos) | `mean(tasa_hurto_motos anual)` 2022–2026 (variable usada en $K$-means) | Tasa promedio quinquenal de hurto a motocicletas por 100.000 hab. |
| `tasa_total_prom` | `numeric` | No nula (`0 NA`) | `[761,216, 9.743,590]` (`19` únicos) | `mean(tasa_hurto_total anual)` 2022–2026 | Tasa promedio quinquenal de hurto agregado (informativa; excluida de ajuste para evitar colinealidad). |
| `poblacion_prom` | `numeric` | No nula (`0 NA`) | `[16.682, 1.245.490,4]` (`19` únicos) | `mean(poblacion)` 2022–2026 | Población media proyectada en la ventana 2022–2026. |
| `silueta_localidad` | `numeric` | No nula (`0 NA`) | `[0,0000, 0,7176]` (`19` únicos; media = `0,5211`) | `cluster::silhouette()` sobre distancia euclidiana Z-score | Coeficiente individual de silueta (`0` localidades con silueta negativa; *Los Mártires* = `0` como grupo unitario). |
| `cluster_id` | `integer` | No nula (`0 NA`) | `1`, `2`, `3` (`3` únicos) | Reasignación determinista según centroides | Código entero del clúster territorial (`1` = Céntrico, `2` = Comercial, `3` = Residencial). |
| `cluster_nombre` | `character` | No nula (`0 NA`) | `"Céntrico e Institucional"`, `"Comercial y Automotor"`, `"Residencial y Periférico"` (`3` únicos) | Mapeo desde `cluster_id` | Etiqueta categórica del perfil urbano de criminalidad. |
| `perfil_seguridad` | `character` | No nula (`0 NA`) | 3 perfiles descriptivos por `cluster_id` | Mapeo descriptivo de dominio por `cluster_id` | Descripción criminológica interpretativa mostrada en tooltips de mapas y perfiles de Shiny. |

---

## 5. `panel_consolidado_localidad_anual.parquet`

* **Ruta relativa:** `data/processed/panel_consolidado_localidad_anual.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `95` filas × `20` columnas (`19 localidades × 5 años`)
* **Unidad de observación (grano):** Combinación `Localidad × Año` (`2022`–`2026`).
* **Llave primaria compuesta (`PK`):** `(codigo_localidad, año)`
* **Propósito y uso:** Tabla panel maestra que consolida los indicadores anuales de criminalidad (agregados desde `SIEDCO.csv` mensual) con las métricas agregadas anuales de volumen y sentimiento mediático calculadas exclusivamente sobre las **`993` noticias objetivo** de las 3 modalidades SIEDCO (`es_objetivo_3mod == TRUE`).
* **Linaje:**
  * **Generado por:** [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) (anualización de `panel_delitos_poblacion_mensual.parquet` unida a la agregación anual de las `993` noticias objetivo y relleno `replace_na(..., 0)`).
  * **Consumido por:** [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) (enriquecida con `clusters_localidades_kmeans.parquet` para formar `datos_consolidados_shiny.rds$panel_localidades`) y [`output/entregas/01_primera_entrega/01_entrega_1_propuesta_eda.qmd`](../../output/entregas/01_primera_entrega/01_entrega_1_propuesta_eda.qmd).
* **Controles de auditoría:** Conserva exactamente `95` filas sin valores `NA`, garantizando consistencia de totales (`sum(noticias_conteo) == 993`).

```r
panel_maestro <- arrow::read_parquet(
  here::here("data", "processed", "panel_consolidado_localidad_anual.parquet")
)
```

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Heredado de `panel_delitos_poblacion_mensual` | Código identificador oficial de la localidad. |
| `localidad` | `character` | No nula (`0 NA`) | `19` nombres oficiales | Heredado de `panel_delitos_poblacion_mensual` | Nombre oficial normalizado de la localidad. |
| `año` | `integer` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | Heredado de `panel_delitos_poblacion_mensual` | Año de análisis (`2022`–`2026`). |
| `hurto_personas` | `integer` | No nula (`0 NA`) | `[1.097, 17.656]` | Suma anual desde `panel_delitos_poblacion_mensual` | Conteo anual de hurtos a personas (`SIEDCO.csv`; corte sep. 2026). |
| `hurto_residencias` | `integer` | No nula (`0 NA`) | `[22, 1.229]` | Suma anual desde `panel_delitos_poblacion_mensual` | Conteo anual de hurtos a residencias. |
| `hurto_motos` | `integer` | No nula (`0 NA`) | `[10, 1.058]` | Suma anual desde `panel_delitos_poblacion_mensual` | Conteo anual de hurtos a motocicletas. |
| `poblacion` | `numeric` | No nula (`0 NA`) | `[16.449, 1.252.218]` | Heredado de `panel_delitos_poblacion_mensual` | Población total proyectada por la SDS para la localidad y año. |
| `tasa_hurto_personas` | `numeric` | No nula (`0 NA`) | `[410,33, 15.250,06]` | `round((hurto_personas / poblacion) * 100000, 2)` | Tasa anual de hurto a personas por 100.000 habitantes. |
| `tasa_hurto_residencias` | `numeric` | No nula (`0 NA`) | `[34,01, 337,42]` | `round((hurto_residencias / poblacion) * 100000, 2)` | Tasa anual de hurto a residencias por 100.000 habitantes. |
| `tasa_hurto_motos` | `numeric` | No nula (`0 NA`) | `[14,23, 230,76]` | `round((hurto_motos / poblacion) * 100000, 2)` | Tasa anual de hurto a motocicletas por 100.000 habitantes. |
| `tasa_hurto_total` | `numeric` | No nula (`0 NA`) | `[490,75, 15.719,53]` | `round(((hurto_personas + hurto_residencias + hurto_motos) / poblacion) * 100000, 2)` | Tasa anual agregada de las 3 modalidades por 100.000 habitantes. |
| `noticias_conteo` | `integer` | No nula (`0 NA`) | `[1, 35]` (`sum = 993`) | `dplyr::n()` en noticias objetivo por `(localidad, año)` | Total de noticias de las 3 modalidades objetivo en esa localidad y año. |
| `noticias_dai_conteo` | `integer` | No nula (`0 NA`) | `[1, 35]` | `sum(es_dai_estricto)` en el subconjunto objetivo | Cantidad de noticias objetivo con clasificación DAI estricta (`== noticias_conteo`). |
| `sentimiento_promedio` | `numeric` | No nula (`0 NA`) | `[-0,6750, 0,1958]` | `round(mean(sentimiento_score), 4)` | Promedio anual del sentimiento compuesto sobre las noticias objetivo de la localidad. |
| `sentimiento_nrc` | `numeric` | No nula (`0 NA`) | `[-0,6818, 0,5152]` | `round(mean(score_nrc_es), 4)` | Promedio anual de polaridad con el léxico general `nrc_es` (subconjunto objetivo). |
| `sentimiento_crimen` | `numeric` | No nula (`0 NA`) | `[-0,8500, 0,0311]` | `round(mean(score_crimen_es), 4)` | Promedio anual de polaridad con el léxico especializado `crimen_es` (subconjunto objetivo). |
| `sentimiento_mediana` | `numeric` | No nula (`0 NA`) | `[-0,7000, 0,1452]` | `round(median(sentimiento_score), 4)` | Mediana anual del puntaje compuesto en el subconjunto objetivo. |
| `prop_negativas` | `numeric` | No nula (`0 NA`) | `[0, 100]` % | `round(mean(sentimiento_categoria == "Negativo") * 100, 2)` | Porcentaje (`%`) de noticias objetivo con tono Negativo. |
| `prop_positivas` | `numeric` | No nula (`0 NA`) | `[0, 75]` % | `round(mean(sentimiento_categoria == "Positivo") * 100, 2)` | Porcentaje (`%`) de noticias objetivo con tono Positivo. |
| `prop_neutras` | `numeric` | No nula (`0 NA`) | `[0, 100]` % | `round(mean(sentimiento_categoria == "Neutro") * 100, 2)` | Porcentaje (`%`) de noticias objetivo con tono Neutro. |

---

## 6. `clusters_sentimiento_kmeans.parquet`

* **Ruta relativa:** `data/processed/clusters_sentimiento_kmeans.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `19` filas × `33` columnas (`19` localidades urbanas completas)
* **Llave primaria (`PK`):** `codigo_localidad`
* **Propósito y uso:** Almacena las asignaciones `K-Means` (`Z-score` con `{recipes}`, `nstart = 50`, `set.seed(20261014)`) sobre el perfil de sentimiento puro de `sentometrics` (`sent_nrc`, `sent_crimen` y `prop_neg`, libre de circularidad frente a los clústeres de hurtos), sus coeficientes de silueta `S(i)` (`silueta_sentimiento`, media `0,4013`, `0` negativas en `K = 3`: `10 / 6 / 3`) y las variables auxiliares usadas para el contraste multivariado contra `clusters_localidades_kmeans.parquet` (`ARI = -0,1026`, Fisher `p = 0,8076`, Mantel `r = -0,0251`).
* **Linaje:**
  * **Generado por:** [`scripts/07_clustering_sentimiento.R`](../../scripts/07_clustering_sentimiento.R).
  * **Consumido por:** [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) (`bundle_shiny$clusters_sentimiento`) y [`app/app.R`](../../app/app.R) (Pestaña 4 *Clusters*).

---

* **Siguiente documento:** [`03_artefactos_sentometrics_shiny.md`](./03_artefactos_sentometrics_shiny.md) — Artefactos S3 de `sentometrics`, modelo Elastic Net y bundle de Shiny.
