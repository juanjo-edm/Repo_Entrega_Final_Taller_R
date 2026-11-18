# Capa 1: Diccionario de Datos Crudos (`data/raw/`)

Esta capa almacena los insumos originales descargados desde fuentes oficiales del Distrito y Google News RSS, antes de aplicar filtros espaciales, homologación de nombres o limpieza de texto.

* **Volver al índice del diccionario:** [`README.md`](./README.md)
* **Siguiente capa:** [`02_tablas_procesadas.md`](./02_tablas_procesadas.md)

---

## Tabla de Contenido

1. [`SIEDCO.csv`](#1-siedcocsv) — Registro mensual oficial de delitos por localidad (OAIEE / SDSCJ)
2. [`localidades_bogota_raw.geojson`](#2-localidades_bogota_rawgeojson) — Capa cartográfica y conteos delictivos oficiales (SDSCJ / SIEDCO)
3. [`poblacion_localidades_raw.parquet`](#3-poblacion_localidades_rawparquet) — Pirámide de proyecciones demográficas (SDS)
4. [`noticias_google_news_consolidado.parquet` y `.rds`](#4-noticias_google_news_consolidadoparquet-y-rds) — Corpus consolidado de prensa digital

---

## 1. `SIEDCO.csv`

* **Ruta relativa:** `data/raw/delitos/SIEDCO.csv`
* **Formato / Clase en R:** CSV delimitado por punto y coma (`;`), codificación `UTF-8` (`data.table` / `tbl_df`)
* **Dimensiones verificadas:** `376.185` filas × `12` columnas
* **Unidad de observación (grano):** Microdato agregado por hecho delictivo, sexo, arma, rango vital, franja horaria, año, mes y localidad (`2018`–septiembre de `2026`).
* **Propósito y uso:** Constituye la fuente oficial mensual de frecuencia exacta usada por [`procesamiento_delitos.R`](../../scripts/02_procesamiento/01_delitos/procesamiento_delitos.R) para construir las series mensuales de `hurto_personas`, `hurto_residencias` y `hurto_motos` (enero de 2022 a septiembre de 2026) que alimentan el clustering $K$-means y el vector objetivo real de Elastic Net.
* **Linaje:**
  * **Generado por:** [`scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R`](../../scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R) (`https://oaiee.scj.gov.co/DatosDescarga/SIEDCO.csv`).
  * **Consumido por:** [`scripts/02_procesamiento/01_delitos/procesamiento_delitos.R`](../../scripts/02_procesamiento/01_delitos/procesamiento_delitos.R).

```r
siedco_raw <- data.table::fread(
  here::here("data", "raw", "delitos", "SIEDCO.csv"),
  sep = ";", encoding = "UTF-8",
  select = c("ANIO", "MES", "HECHO", "LOCALIDAD", "COD_LOCALIDAD", "CANTIDAD")
)
```

| Campo | Tipo (`R`) | Dominio / Valores observados | Descripción |
| :--- | :---: | :--- | :--- |
| `ANIO` | `integer` | `[2018, 2026]` (el estudio filtra `2022:2026`) | Año de ocurrencia del hecho delictivo. |
| `MES` | `integer` | `1..12` (en `2026`, `1..9`) | Mes calendario del registro. |
| `HECHO` | `character` | `12` hechos DAI (se filtran `HURTO A PERSONAS`, `HURTO A RESIDENCIAS`, `HURTO MOTOCICLETAS`) | Tipología delictiva oficial SIEDCO. |
| `LOCALIDAD` | `character` | Nombres de localidades de Bogotá (homologados con tildes en procesamiento) | Nombre crudo de la localidad. |
| `COD_LOCALIDAD` | `integer` | `1..19` urbanas + rurales/sin asignación (se filtra `1:19`) | Código oficial de la localidad. |
| `CANTIDAD` | `integer` | `[1, 275]` | Número de casos registrados en la celda respectiva. |
| `SEXO`, `ARMA_EMPLEADA`, `RANGO_VITAL`, `RANGO_DEL_DIA`, `Fecha de consulta`, `Datos actualizados hasta` | `character` | Variables descriptivas complementarias del registro SIEDCO | Metadatos sociodemográficos, modales y de corte oficial de actualización. |

---

## 2. `localidades_bogota_raw.geojson`

* **Ruta relativa:** `data/raw/delitos/localidades_bogota_raw.geojson`
* **Formato / Clase en R:** GeoJSON vectorial (`sf`, `data.frame`), proyección **WGS 84 (`EPSG:4326`)**
* **Dimensiones verificadas:** `21` filas × `138` columnas
* **Unidad de observación (grano):** Unidad territorial oficial (`CMIULOCAL`): 19 localidades urbanas (`"01"`–`"19"`), 1 localidad rural (`"20"` Sumapaz) y 1 categoría sin georreferenciación (`"99"` Sin Localización).
* **Llave primaria (`PK`):** `CMIULOCAL`
* **Propósito y uso:** Provee los polígonos oficiales de las localidades de Bogotá para cartografía en `{sf}` / `{leaflet}` y contiene series anuales comparativas de referencia publicadas por la SDSCJ.
* **Linaje:**
  * **Generado por:** [`scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R`](../../scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R) (desde Datos Abiertos Bogotá, `dai_geojson.zip`).
  * **Consumido por:** [`scripts/05_export_insumos_shiny.R`](../../scripts/05_export_insumos_shiny.R) y [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd) para extraer la columna `geometry` simplificada topológicamente (`dTolerance = 0.0005`) en `EPSG:4326`.

```r
geo_raw <- sf::st_read(
  here::here("data", "raw", "delitos", "localidades_bogota_raw.geojson"),
  quiet = TRUE
)
```

### 1.1 Campos de Identificación, Corte y Geometría (6 campos)

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `CMIULOCAL` | `character` | No nula (`0 NA`) | `"01"`..`"19"`, `"20"`, `"99"` (21 únicos) | Fuente SDSCJ | Código identificador de la localidad (`"20"` = Sumapaz, `"99"` = Sin Localización). |
| `CMNOMLOCAL` | `character` | No nula (`0 NA`) | `"Usaquén"`, `"Candelaria"`, `"Sin Localización"`, etc. (21 únicos) | Fuente SDSCJ | Nombre oficial de la unidad territorial en la capa SDSCJ (sin normalizar `"Candelaria"`). |
| `CMMES` | `character` | No nula (`0 NA`) | `"Ene-Sep (2018vs2026)"` (constante) | Metadato SDSCJ | Indica el corte calendario acumulado de enero a septiembre para comparar 2018–2026. |
| `Shape_Leng` | `numeric` | No nula (`0 NA`) | `0` (constante en el recurso actual) | Atributo GIS origen | Longitud perimetral heredada de la capa vectorial de origen. |
| `Shape_Area` | `numeric` | No nula (`0 NA`) | `[0, 0.063549]` (`0` para `"99"` Sin Localización) | Atributo GIS origen | Área del polígono en grados cuadrados (`EPSG:4326`). |
| `geometry` | `sfc_POLYGON` | No nula (`0 NA`) | Polígonos en `WGS 84` (vacío geométrico para `"99"`) | Capa vectorial SDSCJ | Geometría poligonal de cada localidad empleada en los mapas coropléticos de Shiny. |

### 1.2 Familias Delictivas y Estructura de los 132 Campos Estadísticos (`12 × 11`)

Los 132 atributos numéricos siguen el patrón `<PREFIJO><SUFIJO>`, combinando **12 familias oficiales de delitos** por **11 variables temporales/resumen**:

#### Prefijos de las 12 Familias Oficiales (`<PREFIJO>`)

| Prefijo | Delito de Alto Impacto (SDSCJ) | Uso en el proyecto | Rango conteo 2022–2026 | Total distrital 2026 (`*TOTAL`) |
| :--- | :--- | :--- | :---: | :---: |
| **`CMHP`** | Hurto a personas | **Variable eje** (panel delitos, tasas, $K$-means y Shiny) | `[0, 22.781]` | `86.376` |
| **`CMHR`** | Hurto a residencias | **Variable eje** (panel delitos, tasas, $K$-means y Shiny) | `[0, 1.674]` | `5.036` |
| **`CMHM`** | Hurto a motocicletas | **Variable eje** (panel delitos, tasas, $K$-means y Shiny) | `[0, 1.472]` | `3.392` |
| `CMHC` | Hurto a comercio | Contexto DAI en fuente cruda | `[0, 1.783]` | `6.734` |
| `CMHA` | Hurto a automotores | Contexto DAI en fuente cruda | `[0, 1.181]` | `2.297` |
| `CMHF` | Hurto a entidades financieras | Contexto DAI en fuente cruda | `[0, 7]` | `4` |
| `CMH` | Homicidios comunes | Contexto DAI en fuente cruda | `[0, 187]` | `819` |
| `CMLP` | Lesiones personales | Contexto DAI en fuente cruda | `[0, 2.061]` | `17.636` |
| `CMDS` | Delitos sexuales | Contexto DAI en fuente cruda | `[0, 878]` | `6.613` |
| `CMVI` | Violencia intrafamiliar | Contexto DAI en fuente cruda | `[0, 4.620]` | `43.013` |
| `CME` | Extorsión | Contexto DAI en fuente cruda | `[0, 310]` | `1.639` |
| `CMS` | Secuestro | Contexto DAI en fuente cruda | `[0, 18]` | `23` |

#### Sufijos Temporales y de Resumen (`<SUFIJO>`)

| Sufijo | Cantidad de columnas | Tipo (`R`) | Nulabilidad | Fórmula / Significado |
| :--- | :---: | :---: | :---: | :--- |
| `18CONT` .. `21CONT` | `4 × 12 = 48` | `numeric` | `0 NA` | Conteo acumulado enero–septiembre para los años 2018, 2019, 2020 y 2021 (fuera de la ventana 2022–2026). |
| `22CONT` .. `26CONT` | `5 × 12 = 60` | `numeric` | `0 NA` | Conteo acumulado enero–septiembre para los años **2022 a 2026** (cifra de contraste oficial; el panel mensual del proyecto usa `SIEDCO.csv`). |
| `VAR` | `1 × 12 = 12` | `numeric` | `0 NA` | Variación porcentual interanual 2026 vs. 2025: `round((26CONT - 25CONT) / 25CONT * 100, 2)`. |
| `TOTAL` | `1 × 12 = 12` | `numeric` | `0 NA` | Suma distrital del año 2026 (`sum(*26CONT)` sobre las 21 filas), repetida como constante en cada registro. |

> **Controles de auditoría en ingesta:** `descarga_delitos_sdscj.R` verifica la descarga de `SIEDCO.csv` y del GeoJSON con columnas `*26CONT`.

---

## 3. `poblacion_localidades_raw.parquet`

* **Ruta relativa:** `data/raw/poblacion/poblacion_localidades_raw.parquet`
* **Formato / Clase en R:** Apache Parquet (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `131.502` filas × `8` columnas
* **Unidad de observación (grano):** Combinación `ANO × CODIGO_LOCALIDAD × SEXO × EDAD` (pirámide poblacional desagregada por edad simple).
* **Llave primaria compuesta (`PK`):** `(ANO, CODIGO_LOCALIDAD, SEXO, EDAD)`
* **Propósito y uso:** Proporciona la serie oficial de población proyectada de la Secretaría Distrital de Salud (SDS) entre 2005 y 2035. Se agrega por localidad y año en 2022–2026 para construir el denominador de las tasas por 100.000 habitantes.
* **Linaje:**
  * **Generado por:** [`scripts/01_ingesta/02_poblacion/descarga_poblacion_sds.R`](../../scripts/01_ingesta/02_poblacion/descarga_poblacion_sds.R) (API CKAN de Datos Abiertos Bogotá con respaldo CSV).
  * **Consumido por:** [`scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R`](../../scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R).

```r
pob_raw <- arrow::read_parquet(
  here::here("data", "raw", "poblacion", "poblacion_localidades_raw.parquet")
)
```

### 2.1 Descripción de Campos (8 columnas)

| Campo | Tipo (`R` / Arrow) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `ANO` | `numeric` (`double`) | No nula (`0 NA`) | `[2005, 2035]` (31 años únicos) | Fuente SDS | Año calendario de la proyección demográfica. El estudio usa `2022:2026`. |
| `CODIGO_LOCALIDAD` | `numeric` (`double`) | No nula (`0 NA`) | `0`..`20` (21 códigos únicos) | Fuente SDS | Código oficial: `0` = total Bogotá D.C., `1..19` = localidades urbanas, `20` = Sumapaz. En procesamiento se excluye `0` y luego `20` al cruzar con delitos. |
| `NOMBRE_LOCALIDAD` | `character` | No nula (`0 NA`) | `"Bogotá"`, `"Usaquén"`, ..., `"Sumapaz"` (21 únicos) | Fuente SDS | Nombre oficial asociado al código de localidad. |
| `SEXO` | `character` | No nula (`0 NA`) | `"Hombres"`, `"Mujeres"` (2 únicos) | Fuente SDS | Sexo biológico de la proyección poblacional. |
| `EDAD` | `numeric` (`double`) | No nula (`0 NA`) | `[0, 100]` (101 edades simples) | Fuente SDS | Edad simple en años cumplidos (`100` agrupa 100 años y más). |
| `CURSODEVIDA` | `character` | No nula (`0 NA`) | `"Primera Infancia"`, `"Infancia"`, `"Adolescencia"`, `"Juventud"`, `"Adultez"`, `"Vejez"` (6 únicos) | Fuente SDS | Categoría de ciclo vital según clasificación de la SDS. |
| `GRUPOEDAD` | `character` | No nula (`0 NA`) | `"00 a 11"`, `"12 a 17"`, `"18 a 28"`, `"29 a 59"`, `"60 o más"` (5 únicos) | Fuente SDS | Rango etario agregado correspondiente al curso de vida. |
| `POBLACION` | `numeric` (`double`) | No nula (`0 NA`) | `[0, 79.199]` (14.682 valores distintos) | Proyección SDS | Número proyectado de habitantes residentes en la celda demográfica. |

> **Controles de auditoría en ingesta:** `descarga_poblacion_sds.R` verifica que todos los años del intervalo `2022:2026` estén presentes en `ANO`.

---

## 4. `noticias_google_news_consolidado.parquet` y `.rds`

* **Rutas relativas:**
  * `data/raw/noticias/noticias_google_news_consolidado.parquet` (formato principal)
  * `data/raw/noticias/noticias_google_news_consolidado.rds` (respaldo binario nativo de R con idéntica estructura)
* **Formato / Clase en R:** Apache Parquet / RDS (`tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `3.916` filas × `16` columnas
* **Unidad de observación (grano):** Artículo periodístico único deduplicado por URL canónica (`enlace`) y titular normalizado (`titulo`).
* **Llave primaria (`PK`):** `enlace` (y `titulo` único en los 3.916 registros)
* **Propósito y uso:** Consolida el corpus de prensa digital recopilado mediante Google News RSS para las 19 localidades urbanas entre enero de 2022 y septiembre de 2026, junto con un primer etiquetado preliminar de medio, delito y confianza geográfica.
* **Linaje:**
  * **Generado por:** [`scripts/01_ingesta/03_noticias/scraping_google_news.R`](../../scripts/01_ingesta/03_noticias/scraping_google_news.R).
  * **Consumido por:** [`scripts/02_procesamiento/03_noticias/procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R).

```r
noticias_raw <- arrow::read_parquet(
  here::here("data", "raw", "noticias", "noticias_google_news_consolidado.parquet")
)
```

### 3.1 Descripción de Campos (16 columnas)

| Campo | Tipo (`R`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `fecha` | `Date` | No nula (`0 NA`) | `[2022-01-01, 2026-09-30]` (527 fechas únicas) | `<pubDate>` RSS normalizada (`as.Date`) | Fecha de publicación de la noticia dentro de la ventana del estudio. |
| `año` | `integer` | No nula (`0 NA`) | `2022..2026` (5 únicos) | `lubridate::year(fecha)` | Año de publicación del artículo. |
| `mes` | `integer` | No nula (`0 NA`) | `1..12` (12 únicos; 2026 hasta mes `9`) | `lubridate::month(fecha)` | Mes numérico de publicación. |
| `año_mes` | `character` | No nula (`0 NA`) | `"2022-01"` a `"2026-09"` (57 meses únicos) | `format(fecha, "%Y-%m")` | Periodo año-mes en formato `YYYY-MM`. |
| `trimestre` | `character` | No nula (`0 NA`) | `"2022-Q1"` a `"2026-Q3"` (19 únicos) | `paste0(año, "-Q", quarter(fecha))` | Trimestre calendario de publicación. |
| `semana_año` | `integer` | No nula (`0 NA`) | `1..52` (52 únicos) | `lubridate::isoweek(fecha)` | Número de semana ISO dentro del año. |
| `localidad` | `character` | No nula (`0 NA`) | 19 localidades urbanas oficiales (ej. `"Antonio Nariño"`, `"Suba"`) | Catálogo de consulta RSS con filtros anti-homonimia | Localidad de Bogotá a la que corresponde el artículo. |
| `confianza_geografica` | `character` | No nula (`0 NA`) | `"Alta"` (532), `"Media"` (3.384) | Reglas de barrios/hitos sobre `titulo + cuerpo` | `"Alta"` si menciona barrios o hitos específicos de la localidad; `"Media"` si se respalda por el anclaje de consulta. |
| `fuente` | `character` | No nula (`0 NA`) | 138 medios/dominios (ej. `bogota.gov.co`, `www.infobae.com`) | `<source>` RSS (fallback `"Prensa Digital"`) | Nombre o dominio del medio editorial que publicó la nota. |
| `tipo_medio` | `character` | No nula (`0 NA`) | `"Institucional"` (1.532), `"Prensa Digital General"` (875), `"Nativo Digital"` (874), `"Prensa Tradicional"` (449), `"Television y Radio"` (149), `"Prensa Local y Comunitaria"` (37) | Reglas regex sobre `fuente + enlace` | Tipología editorial del medio de comunicación. |
| `delito_alto_impacto` | `character` | No nula (`0 NA`) | 15 categorías preliminares (ej. `"Homicidio"`, `"Hurto de bicicletas"`, `"Hurto a personas"`) | Clasificador regex inicial en `scraping_google_news.R` | Etiqueta delictiva preliminar asignada durante la consolidación de ingesta (luego refinada en `procesamiento_noticias.R`). |
| `tipo_delito_dominante` | `character` | No nula (`0 NA`) | Idéntico a `delito_alto_impacto` (15 únicos) | Copia directa de `delito_alto_impacto` | Alias de compatibilidad de la clasificación preliminar en ingesta. |
| `titulo` | `character` | No nula (`0 NA`) | 3.916 titulares únicos | `<title>` RSS con `str_squish()` | Titular de la noticia; clave de segunda deduplicación. |
| `resumen` | `character` | No nula (`0 NA`) | 3.838 resúmenes únicos | `<description>` RSS depurado | Extracto o entradilla editorial de la noticia. |
| `cuerpo` | `character` | No nula (`0 NA`) | 3.907 textos únicos | Extracción web (`coalesce(cuerpo, resumen)`) | Texto completo crudo recolectado (puede conservar ruido HTML o avisos de cookies antes del módulo de procesamiento). |
| `enlace` | `character` | No nula (`0 NA`) | 3.916 URLs únicas | `<link>` RSS sin parámetros `?utm_*`/`ref_*`/`fbclid` | URL canónica de origen; clave de primera deduplicación y enlace clickable en Shiny. |

> **Controles de auditoría en ingesta:** Se exige rango `[2022-01-01, 2026-09-30]`, unicidad por `enlace` y `titulo`, y cero `NA` en `fecha` y `titulo`.
