# Capa 2: Diccionario de Tablas Procesadas (`data/processed/*.parquet`)

Esta capa almacena los cinco conjuntos de datos tabulares limpios, cruzados y enriquecidos en formato **Apache Parquet**, abarcando las **19 localidades urbanas** de Bogotá D.C. en el periodo **2022–2026**.

* **Capa anterior:** [`01_datos_crudos.md`](./01_datos_crudos.md)
* **Índice del diccionario:** [`README.md`](./README.md)
* **Siguiente capa:** [`03_artefactos_sentometrics_shiny.md`](./03_artefactos_sentometrics_shiny.md)

---

## Tabla de Contenido

1. [`delitos_localidad_anual.parquet`](#1-delitos_localidad_anualparquet) — Conteos oficiales de hurtos por localidad y año (`95 × 6`)
2. [`panel_delitos_poblacion_localidad.parquet`](#2-panel_delitos_poblacion_localidadparquet) — Panel de delitos, población y tasas por 100.000 hab. (`95 × 11`)
3. [`noticias_procesadas.parquet`](#3-noticias_procesadasparquet) — Microdatos del corpus de prensa limpios, clasificados y calificados (`3.916 × 42`)
4. [`clusters_localidades_kmeans.parquet`](#4-clusters_localidades_kmeansparquet) — Tipología territorial $K$-means por perfiles de hurto (`19 × 11`)
5. [`panel_consolidado_localidad_anual.parquet`](#5-panel_consolidado_localidad_anualparquet) — Panel maestro criminalidad–demografía–sentimiento (`95 × 20`)

---

## 1. `delitos_localidad_anual.parquet`

* **Ruta relativa:** `data/processed/01_delitos/delitos_localidad_anual.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `95` filas × `6` columnas (`19 localidades × 5 años`)
* **Unidad de observación (grano):** Combinación `Localidad × Año` (`2022`–`2026`).
* **Llave primaria compuesta (`PK`):** `(codigo_localidad, año)`
* **Llaves foráneas / de cruce (`FK`):** `codigo_localidad` vincula con [`localidades_bogota_raw.geojson`](./01_datos_crudos.md#1-localidades_bogota_rawgeojson) (`CMIULOCAL`) y [`poblacion_localidades_raw.parquet`](./01_datos_crudos.md#2-poblacion_localidades_rawparquet) (`CODIGO_LOCALIDAD`).
* **Propósito y uso:** Estandariza los conteos oficiales de las tres modalidades de hurto seleccionadas (`CMHP`, `CMHR`, `CMHM`) desde formato ancho (`22CONT`–`26CONT`) a formato largo en panel equilibrado, normalizando acentos y homologando `"Candelaria"` a `"La Candelaria"`.
* **Linaje:**
  * **Generado por:** [`scripts/02_procesamiento/01_delitos/procesamiento_delitos.R`](../../scripts/02_procesamiento/01_delitos/procesamiento_delitos.R) (a partir de `localidades_bogota_raw.geojson`).
  * **Consumido por:** [`scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R`](../../scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R).
* **Controles de auditoría:** Exclusión explícita de códigos `"20"` (Sumapaz) y `"99"` (Sin Localización); `stopifnot()` verifica exactamente `95` filas, `19` localidades únicas y ausencia de valores `NA`.

```r
delitos_anual <- arrow::read_parquet(
  here::here("data", "processed", "01_delitos", "delitos_localidad_anual.parquet")
)
```

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | `CMIULOCAL` (GeoJSON crudo) | Código oficial DANE/Distrito a dos dígitos para las 19 localidades urbanas. |
| `localidad` | `character` | No nula (`0 NA`) | `"Usaquén"`, `"La Candelaria"`, ..., `"Ciudad Bolívar"` (`19` únicos) | `CMNOMLOCAL` homologado (`"Candelaria"` → `"La Candelaria"`) | Nombre oficial estandarizado con tildes de la localidad. |
| `año` | `numeric` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos enteros) | Extraído del sufijo `22CONT`..`26CONT` + `2000` | Año del corte acumulado enero–septiembre reportado por la SDSCJ. |
| `hurto_personas` | `numeric` | No nula (`0 NA`) | `[870, 22.781]` (`95` únicos) | `CMHP{yy}CONT` | Conteo acumulado de denuncias/casos de hurto a personas en la localidad y año. |
| `hurto_residencias` | `numeric` | No nula (`0 NA`) | `[21, 1.674]` (`87` únicos) | `CMHR{yy}CONT` | Conteo acumulado de hurtos a residencias en la localidad y año. |
| `hurto_motos` | `numeric` | No nula (`0 NA`) | `[7, 1.472]` (`85` únicos) | `CMHM{yy}CONT` | Conteo acumulado de hurtos a motocicletas en la localidad y año. |

---

## 2. `panel_delitos_poblacion_localidad.parquet`

* **Ruta relativa:** `data/processed/02_poblacion/panel_delitos_poblacion_localidad.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `95` filas × `11` columnas (`19 localidades × 5 años`)
* **Unidad de observación (grano):** Combinación `Localidad × Año` (`2022`–`2026`).
* **Llave primaria compuesta (`PK`):** `(codigo_localidad, año)`
* **Propósito y uso:** Integra los conteos delictivos con la población total proyectada por la Secretaría de Salud para relativizar la incidencia mediante tasas por cada `100.000` habitantes, corrigiendo el sesgo por tamaño poblacional antes del clustering y del análisis panel.
* **Linaje:**
  * **Generado por:** [`scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R`](../../scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R) (cruce de `delitos_localidad_anual.parquet` con `poblacion_localidades_raw.parquet` filtrando `CODIGO_LOCALIDAD != 0`).
  * **Consumido por:**
    * [`scripts/04_clustering_kmeans.R`](../../scripts/04_clustering_kmeans.R) (insumo de los promedios 2022–2026 para clustering).
    * [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) (base para el panel maestro y para construir la variable objetivo mensual del Elastic Net).
    * [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).
* **Controles de auditoría:** Se verifica unión completa sin pérdida de filas (`95` registros) y población estrictamente positiva en todos los pares `(codigo_localidad, año)`.

```r
panel_delitos_pob <- arrow::read_parquet(
  here::here("data", "processed", "02_poblacion", "panel_delitos_poblacion_localidad.parquet")
)
```

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Heredado de `delitos_localidad_anual` | Código identificador oficial de la localidad urbana. |
| `localidad` | `character` | No nula (`0 NA`) | `"Usaquén"`, ..., `"Ciudad Bolívar"` (`19` únicos) | Heredado de `delitos_localidad_anual` | Nombre homologado de la localidad. |
| `año` | `numeric` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | Heredado de `delitos_localidad_anual` | Año de análisis (`2022`–`2026`). |
| `hurto_personas` | `numeric` | No nula (`0 NA`) | `[870, 22.781]` (`95` únicos) | Heredado de `delitos_localidad_anual` | Casos acumulados de hurto a personas (corte ene–sep). |
| `hurto_residencias` | `numeric` | No nula (`0 NA`) | `[21, 1.674]` (`87` únicos) | Heredado de `delitos_localidad_anual` | Casos acumulados de hurto a residencias (corte ene–sep). |
| `hurto_motos` | `numeric` | No nula (`0 NA`) | `[7, 1.472]` (`85` únicos) | Heredado de `delitos_localidad_anual` | Casos acumulados de hurto a motocicletas (corte ene–sep). |
| `poblacion` | `numeric` | No nula (`0 NA`) | `[16.449, 1.252.218]` (`94` únicos) | $\sum_{\text{sexo, edad}} \text{POBLACION}$ por `(CODIGO_LOCALIDAD, ANO)` | Proyección oficial total de habitantes de la localidad en el año correspondiente. |
| `tasa_hurto_personas` | `numeric` | No nula (`0 NA`) | `[410,33, 13.348,28]` (`95` únicos) | `round((hurto_personas / poblacion) * 100000, 2)` | Tasa de hurto a personas por cada 100.000 habitantes. |
| `tasa_hurto_residencias` | `numeric` | No nula (`0 NA`) | `[27,73, 398,13]` (`95` únicos) | `round((hurto_residencias / poblacion) * 100000, 2)` | Tasa de hurto a residencias por cada 100.000 habitantes. |
| `tasa_hurto_motos` | `numeric` | No nula (`0 NA`) | `[11,45, 291,23]` (`94` únicos) | `round((hurto_motos / poblacion) * 100000, 2)` | Tasa de hurto a motocicletas por cada 100.000 habitantes. |
| `tasa_hurto_total` | `numeric` | No nula (`0 NA`) | `[490,75, 13.730,22]` (`95` únicos) | `round(((hurto_personas + hurto_residencias + hurto_motos) / poblacion) * 100000, 2)` | Tasa agregada de las tres modalidades de hurto por cada 100.000 habitantes. |

---

## 3. `noticias_procesadas.parquet`

* **Ruta relativa:** `data/processed/03_noticias/noticias_procesadas.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `3.916` filas × `42` columnas
* **Unidad de observación (grano):** Artículo periodístico individual único (`doc_1` a `doc_3916`, ordenado cronológicamente por `localidad` y `fecha`).
* **Llave primaria (`PK`):** `id` (y unicidad funcional en `enlace` y `titulo`).
* **Llaves foráneas / de cruce (`FK`):**
  * `id` enlaza fila a fila con `03_sentiment_scores.rds`, `04_peak_docs.rds`, `05_sento_measures.rds$attribWeights$W` y `08_attributions.rds`.
  * `localidad` y `año` enlazan con `panel_consolidado_localidad_anual.parquet`.
  * `cluster_id` enlaza con `clusters_localidades_kmeans.parquet`.
* **Propósito y uso:** Constituye la tabla maestra a nivel de documento del proyecto. Se construye en dos etapas secuenciales: primero [`procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R) limpia HTML/cookies/anuncios, añade métricas de longitud, clasifica jerárquicamente la taxonomía DAI (`32` columnas iniciales); luego [`03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) adjunta los puntajes de sentimiento léxico/TF-IDF y la pertenencia al clúster territorial (`+10` columnas, sobrescribiendo el archivo hasta alcanzar `42` columnas).
* **Linaje:**
  * **Generado por:** [`scripts/02_procesamiento/03_noticias/procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R) (escritura inicial) y [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) (enriquecimiento y escritura final).
  * **Consumido por:** [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R), [`scripts/06_descriptivos_corpus.R`](../../scripts/06_descriptivos_corpus.R), [`notebook/entregas/01_entrega_1_propuesta_eda.qmd`](../../notebook/entregas/01_entrega_1_propuesta_eda.qmd) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).
* **Controles de auditoría:** Se verifica alineación exacta `all(id == corpus_meta$id)` entre las filas del Parquet y los documentos del `sento_corpus`, conservación exacta de los `3.916` registros y ausencia de `NA` salvo en `confianza_dai` (`794` casos `"No DAI"`) y `motivo_exclusion` (`3.122` casos `es_dai_amplio == TRUE`).

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
| `modalidad_dai` | `character` | No nula (`0 NA`) | `20` modalidades: `hurto_automotores` (`575`), `hurto_no_identificado` (`540`), `hurto_personas` (`519`), `homicidio` (`452`), `hurto_comercio` (`349`), `nodai_sin_hecho_delictivo` (`307`), `nodai_operatividad` (`184`), `hurto_celulares` (`143`), `hurto_residencias` (`140`), `hurto_motocicletas` (`116`), `nodai_politica_seguridad` (`105`), `lesiones_personales` (`80`), `nodai_microtrafico` (`78`), `hurto_bicicletas` (`74`), `extorsion` (`69`), `nodai_otros_hurtos` (`66`), `nodai_otros_delitos` (`54`), `delitos_sexuales` (`32`), `violencia_intrafamiliar` (`17`), `hurto_entidades_financieras` (`16`) | Reglas regex jerárquicas en `procesamiento_noticias.R` | Clasificación granular en 20 categorías (modalidades de hurto, otros DAI y exclusiones No DAI). |
| `campo_clasificacion` | `character` | No nula (`0 NA`) | `"titulo"`, `"resumen"`, `"cuerpo"` (`3` únicos) | Primer campo donde hizo coincidencia la regla regex | Indica el nivel textual que determinó la clasificación de `modalidad_dai`. |
| `delito_sdscj` | `character` | No nula (`0 NA`) | `13` clases: `No DAI` (`794`), `Hurto a personas` (`736`), `Hurto de automotores` (`575`), `Hurto (modalidad no identificada)` (`540`), `Homicidio` (`452`), `Hurto a comercio` (`349`), `Hurto a residencias` (`140`), `Hurto de motocicletas` (`116`), `Lesiones personales` (`80`), `Extorsión` (`69`), `Delitos sexuales` (`32`), `Violencia intrafamiliar` (`17`), `Hurto a entidades financieras` (`16`) | Homologación de `modalidad_dai` (agrupa `hurto_celulares` y `hurto_bicicletas` dentro de `Hurto a personas`) | Categoría oficial homologada con la nomenclatura de la SDSCJ; las 6 modalidades `nodai_*` se consolidan en `"No DAI"`. |
| `confianza_dai` | `character` | Admite `NA` (`794 NA`) | `"Alta"` (`2.472`), `"Baja"` (`404`), `"Media"` (`246`), `<NA>` (`794`) | Derivado de `campo_clasificacion` y `es_dai_amplio` (`NA` si `"No DAI"`) | Certeza de la asignación DAI según el campo de coincidencia (`titulo` → Alta, `resumen` → Media, `cuerpo` → Baja). |
| `es_dai_estricto` | `logical` | No nula (`0 NA`) | `TRUE` / `FALSE` | `delito_sdscj != "No DAI" & delito_sdscj != "Hurto (modalidad no identificada)"` | Indica si el artículo corresponde inequívocamente a una categoría DAI oficial específica. |
| `es_dai_amplio` | `logical` | No nula (`0 NA`) | `TRUE` (`3.122`) / `FALSE` (`794`) | `delito_sdscj != "No DAI"` | Incluye las noticias DAI estrictas más las notas de `"Hurto (modalidad no identificada)"`. |
| `motivo_exclusion` | `character` | Admite `NA` (`3.122 NA`) | `"sin_hecho_delictivo"` (`307`), `"operatividad"` (`184`), `"politica_seguridad"` (`105`), `"microtrafico"` (`78`), `"otros_hurtos"` (`66`), `"otros_delitos"` (`54`), `<NA>` (`3.122`) | Extraído de `modalidad_dai` cuando `es_dai_amplio == FALSE` | Causa de exclusión del marco DAI oficial para las 794 noticias etiquetadas `"No DAI"`. |

### 3.4 Enriquecimiento Léxico (`sentometrics`) y Tipología Territorial (9 campos)

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `word_count` | `numeric` | No nula (`0 NA`) | `[21, 197]` (`116` únicos) | Calculado por `sentometrics::compute_sentiment()` | Conteo de tokens en el texto del `sento_corpus` (`titulo` + `resumen` + primeros `800` caracteres de `cuerpo`). |
| `score_nrc_es` | `numeric` | No nula (`0 NA`) | `[-1,25, 1,4]` (`222` únicos) | Media de columnas `nrc_es--*` en `03_sentiment_scores.rds` (`proportionalPol`) | Polaridad del documento según el léxico general español NRC ajustado por modificadores de valencia. |
| `score_crimen_es` | `numeric` | No nula (`0 NA`) | `[-1,8, 0,8]` (`397` únicos) | Media de columnas `crimen_es--*` en `03_sentiment_scores.rds` (`proportionalPol`) | Polaridad del documento según el léxico especializado de criminalidad en Bogotá (`crimen_es`). |
| `sentimiento_score` | `numeric` | No nula (`0 NA`) | `[-1,0875, 0,9]` (`1.253` únicos) | `round(0.5 * score_nrc_es + 0.5 * score_crimen_es, 4)` | Índice compuesto de sentimiento documental en escala continua; valores negativos expresan tono de alarma/inseguridad. |
| `score_tfidf_compuesto` | `numeric` | No nula (`0 NA`) | `[-15,7244, 22,7264]` (`3.393` únicos) | `0.5 * tfidf_nrc + 0.5 * tfidf_crimen` (esquema `how = "TFIDF"`) | Métrica alternativa ponderada por frecuencia inversa de documento para control metodológico ($r = 0{,}7383$ frente a `proportionalPol`). |
| `sentimiento_categoria` | `character` | No nula (`0 NA`) | `"Negativo"` (`2.580`), `"Positivo"` (`1.129`), `"Neutro"` (`207`) | Negativo `< -0.02`; Neutro `[-0.02, 0.02]`; Positivo `> 0.02` | Clasificación discreta de la polaridad basada en `sentimiento_score`. |
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
* **Propósito y uso:** Almacena la tipología espacial no supervisada obtenida mediante $K$-means sobre las tasas promedio estandarizadas ($Z$-score) de hurto a personas, residencias y motocicletas en el periodo 2022–2026. Evaluando $K \in \{2, 3, 4, 5\}$, el algoritmo selecciona **$K^* = 3$** con silueta promedio global de **`0,5416`**:
  * **Clúster 1 — `Céntrico e Institucional`** (`5` localidades): *La Candelaria, Chapinero, Santa Fe, Teusaquillo, Barrios Unidos*.
  * **Clúster 2 — `Comercial y Automotor`** (`2` localidades): *Los Mártires, Antonio Nariño*.
  * **Clúster 3 — `Residencial y Periférico`** (`12` localidades): *Puente Aranda, Fontibón, Engativá, Usaquén, Tunjuelito, Kennedy, Rafael Uribe Uribe, Suba, San Cristóbal, Ciudad Bolívar, Bosa, Usme*.
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
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Código identificador oficial de la localidad. |
| `localidad` | `character` | No nula (`0 NA`) | `19` nombres oficiales | Heredado de `panel_delitos_poblacion_localidad` | Nombre oficial normalizado de la localidad. |
| `tasa_personas_prom` | `numeric` | No nula (`0 NA`) | `[619,698, 8.389,902]` (`19` únicos) | `mean(tasa_hurto_personas)` 2022–2026 (variable usada en $K$-means) | Tasa promedio quinquenal de hurto a personas por 100.000 hab. |
| `tasa_resid_prom` | `numeric` | No nula (`0 NA`) | `[45,292, 217,482]` (`19` únicos) | `mean(tasa_hurto_residencias)` 2022–2026 (variable usada en $K$-means) | Tasa promedio quinquenal de hurto a residencias por 100.000 hab. |
| `tasa_motos_prom` | `numeric` | No nula (`0 NA`) | `[16,616, 178,178]` (`19` únicos) | `mean(tasa_hurto_motos)` 2022–2026 (variable usada en $K$-means) | Tasa promedio quinquenal de hurto a motocicletas por 100.000 hab. |
| `tasa_total_prom` | `numeric` | No nula (`0 NA`) | `[729,754, 8.757,422]` (`19` únicos) | `mean(tasa_hurto_total)` 2022–2026 | Tasa promedio quinquenal de hurto agregado (informativa; excluida de ajuste para evitar colinealidad). |
| `poblacion_prom` | `numeric` | No nula (`0 NA`) | `[16.682, 1.245.490,4]` (`19` únicos) | `mean(poblacion)` 2022–2026 | Población media proyectada en la ventana 2022–2026. |
| `silueta_localidad` | `numeric` | No nula (`0 NA`) | `[-0,2116, 0,7615]` (`19` únicos; media = `0,5416`) | `cluster::silhouette()` sobre distancia euclidiana Z-score | Coeficiente individual de silueta (`Antonio Nariño = -0,2116` marca transición limítrofe). |
| `cluster_id` | `integer` | No nula (`0 NA`) | `1`, `2`, `3` (`3` únicos) | Reasignación determinista según centroides | Código entero del clúster territorial (`1` = Céntrico, `2` = Comercial, `3` = Residencial). |
| `cluster_nombre` | `character` | No nula (`0 NA`) | `"Céntrico e Institucional"`, `"Comercial y Automotor"`, `"Residencial y Periférico"` (`3` únicos) | Mapeo desde `cluster_id` | Etiqueta categórica del perfil urbano de criminalidad. |
| `perfil_seguridad` | `character` | No nula (`0 NA`) | `"Alta criticidad en hurto a personas y residencias (núcleo céntrico)"`; `"Alta concentración de hurto automotor y motocicletas (corredor comercial)"`; `"Tasa per cápita moderada en zonas de alta densidad residencial"` (`3` únicos) | Mapeo descriptivo de dominio por `cluster_id` | Descripción criminológica interpretativa mostrada en tooltips de mapas y perfiles de Shiny. |

---

## 5. `panel_consolidado_localidad_anual.parquet`

* **Ruta relativa:** `data/processed/panel_consolidado_localidad_anual.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `95` filas × `20` columnas (`19 localidades × 5 años`)
* **Unidad de observación (grano):** Combinación `Localidad × Año` (`2022`–`2026`).
* **Llave primaria compuesta (`PK`):** `(codigo_localidad, año)`
* **Propósito y uso:** Tabla panel maestra que consolida los indicadores objetivos de criminalidad y población con las métricas agregadas anuales de volumen mediático y sentimiento calculadas sobre `noticias_procesadas.parquet`.
* **Linaje:**
  * **Generado por:** [`scripts/03_analisis_sentometrics.R`](../../scripts/03_analisis_sentometrics.R) (unión izquierda de `panel_delitos_poblacion_localidad.parquet` con la agregación anual de `noticias_procesadas.parquet` y relleno `replace_na(..., 0)`).
  * **Consumido por:** [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) (donde se enriquece con `clusters_localidades_kmeans.parquet` para formar `datos_consolidados_shiny.rds$panel_localidades`) y [`notebook/entregas/01_entrega_1_propuesta_eda.qmd`](../../notebook/entregas/01_entrega_1_propuesta_eda.qmd).
* **Controles de auditoría:** Conserva exactamente `95` filas sin valores `NA`, garantizando que todas las combinaciones `(localidad, año)` tengan al menos `5` noticias capturadas y que `prop_negativas + prop_positivas + prop_neutras ≈ 100%`.

```r
panel_maestro <- arrow::read_parquet(
  here::here("data", "processed", "panel_consolidado_localidad_anual.parquet")
)
```

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Código identificador oficial de la localidad. |
| `localidad` | `character` | No nula (`0 NA`) | `19` nombres oficiales | Heredado de `panel_delitos_poblacion_localidad` | Nombre oficial normalizado de la localidad. |
| `año` | `numeric` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Año de análisis (`2022`–`2026`). |
| `hurto_personas` | `numeric` | No nula (`0 NA`) | `[870, 22.781]` (`95` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Conteo acumulado de hurto a personas (ene–sep). |
| `hurto_residencias` | `numeric` | No nula (`0 NA`) | `[21, 1.674]` (`87` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Conteo acumulado de hurto a residencias (ene–sep). |
| `hurto_motos` | `numeric` | No nula (`0 NA`) | `[7, 1.472]` (`85` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Conteo acumulado de hurto a motocicletas (ene–sep). |
| `poblacion` | `numeric` | No nula (`0 NA`) | `[16.449, 1.252.218]` (`94` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Población total proyectada por la SDS para la localidad y año. |
| `tasa_hurto_personas` | `numeric` | No nula (`0 NA`) | `[410,33, 13.348,28]` (`95` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Tasa de hurto a personas por 100.000 habitantes. |
| `tasa_hurto_residencias` | `numeric` | No nula (`0 NA`) | `[27,73, 398,13]` (`95` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Tasa de hurto a residencias por 100.000 habitantes. |
| `tasa_hurto_motos` | `numeric` | No nula (`0 NA`) | `[11,45, 291,23]` (`94` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Tasa de hurto a motocicletas por 100.000 habitantes. |
| `tasa_hurto_total` | `numeric` | No nula (`0 NA`) | `[490,75, 13.730,22]` (`95` únicos) | Heredado de `panel_delitos_poblacion_localidad` | Tasa agregada de hurtos por 100.000 habitantes. |
| `noticias_conteo` | `integer` | No nula (`0 NA`) | `[5, 88]` (`61` únicos) | `dplyr::n()` en `noticias_procesadas` por `(localidad, año)` | Total de noticias capturadas para la localidad en ese año. |
| `noticias_dai_conteo` | `integer` | No nula (`0 NA`) | `[3, 62]` (`42` únicos) | `sum(es_dai_estricto)` en `noticias_procesadas` | Cantidad de noticias clasificadas estrictamente en una categoría DAI específica. |
| `sentimiento_promedio` | `numeric` | No nula (`0 NA`) | `[-0,5844, 0,3339]` (`95` únicos) | `round(mean(sentimiento_score), 4)` | Promedio anual del sentimiento compuesto en la cobertura mediática de la localidad. |
| `sentimiento_nrc` | `numeric` | No nula (`0 NA`) | `[-0,5401, 0,5642]` (`95` únicos) | `round(mean(score_nrc_es), 4)` | Promedio anual de polaridad calculada con el léxico general `nrc_es`. |
| `sentimiento_crimen` | `numeric` | No nula (`0 NA`) | `[-0,6717, 0,1037]` (`94` únicos) | `round(mean(score_crimen_es), 4)` | Promedio anual de polaridad calculada con el léxico especializado `crimen_es`. |
| `sentimiento_mediana` | `numeric` | No nula (`0 NA`) | `[-0,725, 0,4583]` (`78` únicos) | `round(median(sentimiento_score), 4)` | Mediana anual del puntaje compuesto de sentimiento. |
| `prop_negativas` | `numeric` | No nula (`0 NA`) | `[21,43, 88,89]` (`81` únicos) | `round(mean(sentimiento_categoria == "Negativo") * 100, 2)` | Porcentaje (`%`) de noticias con sentimiento clasificado como Negativo. |
| `prop_positivas` | `numeric` | No nula (`0 NA`) | `[0, 78,57]` (`76` únicos) | `round(mean(sentimiento_categoria == "Positivo") * 100, 2)` | Porcentaje (`%`) de noticias con sentimiento clasificado como Positivo. |
| `prop_neutras` | `numeric` | No nula (`0 NA`) | `[0, 16,67]` (`62` únicos) | `round(mean(sentimiento_categoria == "Neutro") * 100, 2)` | Porcentaje (`%`) de noticias con sentimiento clasificado como Neutro. |

---

* **Siguiente documento:** [`03_artefactos_sentometrics_shiny.md`](./03_artefactos_sentometrics_shiny.md) — Artefactos S3 de `sentometrics`, modelo Elastic Net y bundle de Shiny.
