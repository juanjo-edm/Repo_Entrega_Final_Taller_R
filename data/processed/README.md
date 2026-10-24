# Datos Procesados (`data/processed/`)

Esta carpeta contiene los conjuntos de datos limpios, transformados y enriquecidos del proyecto **Hurtos y Sentimiento Mediático en Bogotá (2022-2026)**.

Los archivos se encuentran organizados en dos subcarpetas temáticas:
* **`hurtos/`:** Paneles agregados de criminalidad oficial (SIEDCO / SCJ) y demografía proyectada (DANE / SDS).
* **`noticias/`:** Corpus de prensa depurado, normalizado y calificado con análisis de sentimiento (`sentometrics`).

Todos los conjuntos tabulares se almacenan prioritariamente en formato **Apache Parquet** (con compresión columnar Snappy), garantizando lectura de alta velocidad, tipado estricto e interoperabilidad con Apache Arrow y R.

---

## 1. Estructura de Directorios

```text
data/processed/
├── README.md
├── hurtos/
│   ├── panel_delitos_poblacion_localidad.parquet     # Tasas oficiales por 100k hab (19 locs x 5 años)
│   └── panel_consolidado_localidad_anual.parquet     # Fusión de tasas oficiales con métricas de sentimiento
└── noticias/
    ├── noticias_procesadas.parquet                   # Corpus limpio y deduplicado (3.916 noticias)
    ├── noticias_procesadas.rds                       # Respaldo en formato binario nativo de R
    └── noticias_con_sentimiento.parquet              # Corpus con polaridad léxica NRC calculada
```

---

## 2. Subcarpeta `data/processed/hurtos/`

### 2.1 `panel_delitos_poblacion_localidad.parquet`
* **Script generador:** `scripts/02_limpieza_indicadores.R`
* **Unidad de análisis:** Localidad urbana $\times$ Año calendario ($19 \times 5 = 95$ observaciones).
* **Periodo temporal:** 2022 a 2026.
* **Claves de cruce primarias:** `codigo_localidad` (carácter de 2 dígitos), `año` (entero).
* **Descripción:** Panel balanceado que consolida las denuncias policiales de delitos de alto impacto registradas por la Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ) y la Policía Nacional, cruzadas con las proyecciones poblacionales de la Secretaría Distrital de Salud (SDS) para computar tasas estandarizadas por cada 100.000 habitantes.

#### Diccionario de Variables:
| Variable | Tipo | Descripción y Fórmula Metodológica |
| :--- | :--- | :--- |
| `codigo_localidad` | `character` | Código numérico oficial DANE de dos dígitos (`"01"` a `"19"`). Excluye Sumapaz (`"20"`) y no identificados (`"99"`). |
| `localidad` | `character` | Nombre propio oficial de la localidad urbana con tildes y mayúsculas normativas. |
| `año` | `numeric` | Año del registro delictivo y poblacional ($2022, 2023, 2024, 2025, 2026$). |
| `hurto_personas` | `numeric` | Conteo anual de denuncias por hurto a personas (código SIEDCO `CMHP`). |
| `hurto_residencias` | `numeric` | Conteo anual de denuncias por hurto a residencias (código SIEDCO `CMHR`). |
| `hurto_motos` | `numeric` | Conteo anual de denuncias por hurto a motocicletas (código SIEDCO `CMHM`). |
| `poblacion` | `numeric` | Población total proyectada para la localidad en el año respectivo (fuente oficial SDS / DANE). |
| `tasa_hurto_personas` | `numeric` | Tasa anual de hurto a personas por 100.000 habitantes: $\frac{\text{hurto\_personas}}{\text{poblacion}} \times 100.000$. |
| `tasa_hurto_residencias` | `numeric` | Tasa anual de hurto a residencias por 100.000 habitantes: $\frac{\text{hurto\_residencias}}{\text{poblacion}} \times 100.000$. |
| `tasa_hurto_motos` | `numeric` | Tasa anual de hurto a motos por 100.000 habitantes: $\frac{\text{hurto\_motos}}{\text{poblacion}} \times 100.000$. |
| `tasa_hurto_total` | `numeric` | Tasa consolidada de las tres modalidades por 100.000 habitantes: $\frac{\sum \text{hurtos}}{\text{poblacion}} \times 100.000$. |

---

### 2.2 `panel_consolidado_localidad_anual.parquet`
* **Script generador:** `scripts/03_analisis_sentometrics.R`
* **Unidad de análisis:** Localidad urbana $\times$ Año calendario ($19 \times 5 = 95$ observaciones).
* **Periodo temporal:** 2022 a 2026.
* **Claves de cruce primarias:** `codigo_localidad`, `localidad`, `año`.
* **Descripción:** Base analítica unificada del proyecto. Contiene las 11 variables oficiales de `panel_delitos_poblacion_localidad.parquet` fusionadas mediante `left_join` con los agregados anuales del volumen de cobertura de prensa y el tono del sentimiento mediático extraído de las noticias procesadas.

#### Variables Adicionales Incorporadas:
| Variable | Tipo | Descripción y Cálculo |
| :--- | :--- | :--- |
| `noticias_conteo` | `integer` | Número total de artículos de prensa publicados sobre hechos delictivos en la localidad y año. |
| `sentimiento_promedio` | `numeric` | Media aritmética del puntaje de polaridad léxica proporcional calculado con `sentometrics`. |
| `sentimiento_mediana` | `numeric` | Mediana del puntaje de polaridad léxica, robusta frente a artículos atípicos muy extensos. |
| `prop_negativas` | `numeric` | Porcentaje de noticias con puntaje de sentimiento estrictamente menor a cero ($\% < 0$). |
| `prop_positivas` | `numeric` | Porcentaje de noticias con puntaje de sentimiento estrictamente mayor a cero ($\% > 0$, e.g., operativos o capturas). |
| `prop_neutras` | `numeric` | Porcentaje de noticias con puntaje de polaridad balanceado o neutro ($\% = 0$). |

---

## 3. Subcarpeta `data/processed/noticias/`

### 3.1 `noticias_procesadas.parquet` / `noticias_procesadas.rds`
* **Script generador:** `scripts/02_limpieza_texto_noticias.R`
* **Insumo de origen:** `data/raw/noticias/noticias_google_news_consolidado.parquet`
* **Unidad de análisis:** Artículo periodístico individual único ($3.916$ observaciones, $20$ columnas).
* **Periodo temporal:** `2022-01-01` a `2026-09-30`.
* **Descripción:** Corpus textual completamente depurado. Se han eliminado publicidades repetitivas, widgets de cookies, metadatos multimedia y titulares deportivos o regionales fuera de Bogotá. Se dispone tanto en Parquet para interoperabilidad como en `.rds` para compatibilidad nativa en R.

#### Diccionario de Variables:
| Variable | Tipo | Descripción |
| :--- | :--- | :--- |
| `fecha` | `Date` | Fecha de publicación en formato estándar ISO (`YYYY-MM-DD`). |
| `año` | `numeric` | Año extraído de la fecha de publicación ($2022$ a $2026$). |
| `mes` | `numeric` | Mes numérico ($1$ a $12$). |
| `año_mes` | `character` | Identificador de periodo mensual (`YYYY-MM`). |
| `trimestre` | `character` | Periodo trimestral (`YYYY-T1`, `YYYY-T2`, `YYYY-T3`, `YYYY-T4`). |
| `semana_año` | `numeric` | Semana ISO del año ($1$ a $53$). |
| `localidad` | `character` | Localidad urbana de Bogotá asociada al reporte ($19$ nombres oficiales). |
| `confianza_geografica` | `character` | Grado de certeza espacial: `Alta` (menciona barrios o UPZ) o `Media` (validada por consulta). |
| `fuente` | `character` | Dominio o nombre del medio editorial de procedencia (ej. *eltiempo.com*, *bogota.gov.co*). |
| `tipo_medio` | `character` | Categorización tipológica del medio: *Institucional*, *Prensa Tradicional*, *Televisión y Radio*, *Nativo Digital*, *Prensa Local y Comunitaria*, *Prensa Digital General*. |
| `delito_alto_impacto` | `character` | Tipología penal homóloga clasificada según el sistema oficial SIEDCO / SCJ ($15$ categorías). |
| `tipo_delito_dominante` | `character` | Macrocategoría delictiva para análisis agregados. |
| `titulo` | `character` | Titular periodístico limpio y sin caracteres de control. |
| `resumen` | `character` | Resumen informativo o snippet editorial original. |
| `cuerpo` | `character` | Texto del cuerpo de la noticia tras la remoción de cookies, publicidad y slogans. |
| `texto_completo_nlp` | `character` | Cadena unificada de titular y cuerpo, optimizada para tokenización y modelos de lenguaje. |
| `palabras_titulo` | `integer` | Conteo de palabras en el titular. |
| `palabras_cuerpo` | `integer` | Conteo de palabras en el cuerpo del texto. |
| `caracteres_cuerpo` | `integer` | Longitud total del cuerpo en caracteres. |
| `enlace` | `character` | URL canónica de la noticia sin parámetros de seguimiento ni cadenas `utm_`. |

---

### 3.2 `noticias_con_sentimiento.parquet`
* **Script generador:** `scripts/03_analisis_sentometrics.R`
* **Insumo de origen:** `data/processed/noticias/noticias_procesadas.parquet`
* **Unidad de análisis:** Artículo periodístico calificado ($3.916$ observaciones, $24$ columnas).
* **Descripción:** Extensión analítica del corpus que incorpora las valoraciones cuantitativas de polaridad léxica calculadas con el paquete `sentometrics` a partir del diccionario expandido NRC en español.

#### Variables Específicas de Sentimiento:
| Variable | Tipo | Descripción y Cálculo |
| :--- | :--- | :--- |
| `id` | `character` | Identificador único del documento en el corpus de `sentometrics` (`doc_1`, `doc_2`, ...). |
| `word_count` | `numeric` | Conteo efectivo de palabras procesadas durante la tokenización léxica. |
| `sentimiento_score` | `numeric` | Puntuación de polaridad proporcional: $\frac{\text{palabras positivas} - \text{palabras negativas}}{\text{total palabras clasificadas}}$. Valores negativos indican tono desfavorable. |
| `sentimiento_categoria` | `character` | Clasificación cualitativa discreta: `Negativo` ($< 0$), `Positivo` ($> 0$) o `Neutro` ($= 0$). |

---

## 4. Trazabilidad e Integridad de Datos

Para verificar la integridad de todos los archivos desde la consola de R:

```r
library(arrow)
stopifnot(nrow(read_parquet(here::here("data", "processed", "hurtos", "panel_delitos_poblacion_localidad.parquet"))) == 95)
stopifnot(nrow(read_parquet(here::here("data", "processed", "hurtos", "panel_consolidado_localidad_anual.parquet"))) == 95)
stopifnot(nrow(read_parquet(here::here("data", "processed", "noticias", "noticias_procesadas.parquet"))) == 3916)
stopifnot(nrow(read_parquet(here::here("data", "processed", "noticias", "noticias_con_sentimiento.parquet"))) == 3916)
message("✔ Todas las bases procesadas cumplen con los criterios de integridad y auditoría.")
```
