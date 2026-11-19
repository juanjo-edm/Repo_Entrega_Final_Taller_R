# Capa 4: Tablas de Salida y Auditoría (`output/tables/*.csv`)

Esta capa documenta las **ocho tablas resumen, sensibilidad $K$-means y auditoría** exportadas en formato **CSV** (delimitado por comas, codificación UTF-8) para reportes académicos en Quarto, control de clasificación y validación manual.

* **Capa anterior:** [`03_artefactos_sentometrics_shiny.md`](./03_artefactos_sentometrics_shiny.md)
* **Índice del diccionario:** [`README.md`](./README.md)

---

## Tabla de Contenido

1. [`tabla_clustering_kmeans_perfiles.csv`](#1-tabla_clustering_kmeans_perfilescsv) — Perfiles y siluetas de los clústeres territoriales (`19 × 11`)
2. [`tabla_descriptivos_corpus.csv`](#2-tabla_descriptivos_corpuscsv) — Descriptivos anuales de cobertura, longitud y tono (`5 × 7`)
3. [`tabla_reclasificacion_dai.csv`](#3-tabla_reclasificacion_daicsv) — Matriz de cruce entre etiqueta de scraping y taxonomía SDSCJ (`122 × 3`)
4. [`tabla_conteo_localidad_anio_dai.csv`](#4-tabla_conteo_localidad_anio_daicsv) — Conteos de noticias DAI y cobertura ene–sep por localidad y año (`95 × 5`)
5. [`muestra_validacion_manual_dai.csv`](#5-muestra_validacion_manual_daicsv) — Muestra aleatoria estratificada para auditoría humana (`195 × 10`)
6. [`tabla_sensibilidad_escalamientos_pca.csv`](#6-tabla_sensibilidad_escalamientos_pcacsv) — Sensibilidad $K$-means bajo 5 escalamientos y PCA 2D (`5 × 8`)
7. [`tabla_comparacion_modelos_distancias.csv`](#7-tabla_comparacion_modelos_distanciascsv) — Comparación entre K-Means, PAM, AGNES y GMM (`6 × 7`)
8. [`tabla_asignaciones_modelos_localidad.csv`](#8-tabla_asignaciones_modelos_localidadcsv) — Asignaciones comparativas por localidad en 7 especificaciones (`19 × 11`)

---

## 1. `tabla_clustering_kmeans_perfiles.csv`

* **Ruta relativa:** `output/tables/tabla_clustering_kmeans_perfiles.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `19` filas × `11` columnas
* **Unidad de observación (grano):** Localidad urbana de Bogotá D.C. (`19` localidades).
* **Llave primaria (`PK`):** `codigo_localidad`
* **Propósito y uso:** Es la exportación tabular legible de [`clusters_localidades_kmeans.parquet`](./02_tablas_procesadas.md#4-clusters_localidades_kmeansparquet) para consulta directa en Excel/Quarto e inspección rápida de las tasas promedio, coeficientes de silueta y asignación de clúster (`K* = 3`).
* **Linaje:**
  * **Generado por:** [`scripts/04_clustering_kmeans.R`](../../scripts/04_clustering_kmeans.R).
  * **Consumido por:** Consulta académica y anexos del proyecto (en formato Parquet alimenta al pipeline R).

```r
tabla_clusters <- readr::read_csv(
  here::here("output", "tables", "tabla_clustering_kmeans_perfiles.csv"),
  show_col_types = FALSE
)
```

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Código oficial DANE/Distrito de dos dígitos (conservado con cero a la izquierda). |
| `localidad` | `character` | No nula (`0 NA`) | `19` nombres oficiales | Nombre oficial normalizado de la localidad urbana. |
| `tasa_personas_prom` | `numeric` | No nula (`0 NA`) | `[645,304, 9.337,386]` | Tasa promedio 2022–2026 de hurto a personas por 100.000 hab. (base mensual SIEDCO anualizada). |
| `tasa_resid_prom` | `numeric` | No nula (`0 NA`) | `[44,506, 219,660]` | Tasa promedio 2022–2026 de hurto a residencias por 100.000 hab. |
| `tasa_motos_prom` | `numeric` | No nula (`0 NA`) | `[19,034, 187,432]` | Tasa promedio 2022–2026 de hurto a motocicletas por 100.000 hab. |
| `tasa_total_prom` | `numeric` | No nula (`0 NA`) | `[761,216, 9.743,590]` | Tasa promedio quinquenal agregada por 100.000 hab. |
| `poblacion_prom` | `numeric` | No nula (`0 NA`) | `[16.682, 1.245.490,4]` | Población media proyectada en el periodo 2022–2026. |
| `silueta_localidad` | `numeric` | No nula (`0 NA`) | `[0,0000, 0,7176]` (promedio `0,5211`, `0` negativas) | Coeficiente de silueta individual por localidad bajo distancia euclidiana Z-score. |
| `cluster_id` | `numeric` | No nula (`0 NA`) | `1`, `2`, `3` (`3` únicos) | Identificador entero del clúster territorial (al parsearse desde CSV `readr` lo infiere como `numeric`). |
| `cluster_nombre` | `character` | No nula (`0 NA`) | `"Céntrico e Institucional"`, `"Comercial y Automotor"`, `"Residencial y Periférico"` | Etiqueta descriptiva del clúster territorial asignado. |
| `perfil_seguridad` | `character` | No nula (`0 NA`) | 3 perfiles descriptivos completos | Síntesis criminológica asociada a `cluster_id`. |

---

## 2. `tabla_descriptivos_corpus.csv`

* **Ruta relativa:** `output/tables/tabla_descriptivos_corpus.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `5` filas × `7` columnas (`2022`–`2026`)
* **Unidad de observación (grano):** Año calendario dentro de la ventana efectiva del estudio (`2022`–`2025` completos; `2026` enero–septiembre).
* **Llave primaria (`PK`):** `año`
* **Propósito y uso:** Resume la evolución anual del volumen de noticias, cobertura territorial, número de artículos DAI estrictos, longitud del cuerpo y sentimiento medio compuesto, sirviendo como insumo directo de la tabla `tbl-descriptivos-corpus-anual` en el cuaderno metodológico.
* **Linaje:**
  * **Generado por:** [`scripts/06_descriptivos_corpus.R`](../../scripts/06_descriptivos_corpus.R) (a partir de `noticias_procesadas.parquet` filtrando `!(año == 2026 & mes > 9)`).
  * **Consumido por:** [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

```r
tabla_desc <- readr::read_csv(
  here::here("output", "tables", "tabla_descriptivos_corpus.csv"),
  show_col_types = FALSE
)
```

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `año` | `numeric` | No nula (`0 NA`) | `2022`, `2023`, `2024`, `2025`, `2026` | Agrupación por `año` | Año calendario de publicación (`2026` truncado a septiembre). |
| `noticias` | `numeric` | No nula (`0 NA`) | `448`, `534`, `870`, `994`, `1.070` (`total = 3.916`) | `dplyr::n()` | Número total de artículos recopilados en el año. |
| `noticias_3mod` | `numeric` | No nula (`0 NA`) | `112`, `119`, `211`, `269`, `282` (`total = 993`) | `sum(es_objetivo_3mod)` | Noticias pertenecientes a las 3 modalidades objetivo (`Hurto a personas`, `Hurto a residencias`, `Hurto de motocicletas`). |
| `localidades` | `numeric` | No nula (`0 NA`) | `19` (constante) | `n_distinct(localidad)` | Número de localidades urbanas cubiertas en el año (cobertura completa 19/19 en todos los años). |
| `media_palabras` | `numeric` | No nula (`0 NA`) | `18,7` (`2026`) a `433,2` (`2025`) | `round(mean(palabras_cuerpo), 1)` | Promedio anual de palabras en el cuerpo limpio de la noticia. |
| `mediana_palabras` | `numeric` | No nula (`0 NA`) | `18` (`2026`) a `411` (`2024`) | `median(palabras_cuerpo)` | Mediana anual de palabras en `cuerpo`. |
| `sentimiento_prom` | `numeric` | No nula (`0 NA`) | `[-0,4269, -0,1492]` | `round(mean(sentimiento_score), 4)` | Promedio anual del índice compuesto de sentimiento sobre el corpus objetivo. |

---

## 3. `tabla_reclasificacion_dai.csv`

* **Ruta relativa:** `output/tables/tabla_reclasificacion_dai.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `122` filas × `3` columnas
* **Unidad de observación (grano):** Par único `(delito_alto_impacto, delito_sdscj)`.
* **Llave primaria compuesta (`PK`):** `(delito_alto_impacto, delito_sdscj)`
* **Propósito y uso:** Tabla de auditoría metodológica que documenta cuántas noticias de cada etiqueta original de búsqueda (`delito_alto_impacto`) fueron reasignadas a cada categoría oficial homologada (`delito_sdscj`) o filtradas como `"No DAI"` tras leer `titulo`, `resumen` y `cuerpo`.
* **Linaje:** Generado por [`scripts/02_procesamiento/03_noticias/procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R); empleado para trazabilidad de la limpieza temática en entregas y anexos.

```r
tabla_reclas <- readr::read_csv(
  here::here("output", "tables", "tabla_reclasificacion_dai.csv"),
  show_col_types = FALSE
)
```

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `delito_alto_impacto` | `character` | No nula (`0 NA`) | `15` etiquetas originales de scraping | Categoría asignada originalmente al consultar Google News RSS. |
| `delito_sdscj` | `character` | No nula (`0 NA`) | `13` categorías finales (`11` DAI oficiales + `"Hurto (modalidad no identificada)"` + `"No DAI"`) | Categoría oficial resultante de la clasificación jerárquica textual (`titulo` → `resumen` → `cuerpo`). |
| `n` | `numeric` | No nula (`0 NA`) | `[1, 429]` (`sum(n) = 3.916`) | Frecuencia de artículos que transitaron de `delito_alto_impacto` a `delito_sdscj`. |

---

## 4. `tabla_conteo_localidad_anio_dai.csv`

* **Ruta relativa:** `output/tables/tabla_conteo_localidad_anio_dai.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `95` filas × `5` columnas (`19 localidades × 5 años`)
* **Unidad de observación (grano):** Combinación `Localidad × Año` (`2022`–`2026`).
* **Llave primaria compuesta (`PK`):** `(localidad, año)`
* **Propósito y uso:** Reporta la cobertura informativa agregada por localidad y año bajo tres criterios de filtrado (DAI amplio, DAI estricto y ventana calendario enero–septiembre), permitiendo auditar el impacto de restringir el análisis al corte comparable con los boletines SDSCJ.
* **Linaje:** Generado por [`scripts/02_procesamiento/03_noticias/procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R).

```r
conteo_dai <- readr::read_csv(
  here::here("output", "tables", "tabla_conteo_localidad_anio_dai.csv"),
  show_col_types = FALSE
)
```

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Origen / Fórmula | Descripción |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `localidad` | `character` | No nula (`0 NA`) | `19` nombres oficiales | Agrupación en `noticias_procesadas` | Nombre oficial normalizado de la localidad urbana. |
| `año` | `numeric` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | Agrupación en `noticias_procesadas` | Año calendario (`2022`–`2026`). |
| `noticias_dai` | `numeric` | No nula (`0 NA`) | `[3, 85]` (`50` únicos) | `sum(es_dai_amplio)` | Total de noticias DAI bajo criterio amplio (incluye hurto sin modalidad identificada). |
| `noticias_dai_estricto` | `numeric` | No nula (`0 NA`) | `[3, 62]` (`42` únicos) | `sum(es_dai_estricto)` | Total de noticias clasificadas estrictamente en un tipo DAI oficial específico. |
| `noticias_dai_ene_sep` | `numeric` | No nula (`0 NA`) | `[1, 85]` (`49` únicos) | `sum(es_dai_amplio & ventana_ene_sep)` | Noticias DAI amplio publicadas entre enero y septiembre de cada año. |

---

## 5. `muestra_validacion_manual_dai.csv`

* **Ruta relativa:** `output/tables/muestra_validacion_manual_dai.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `195` filas × `10` columnas (`13 categorías delito_sdscj × hasta 15 casos muestreados`, semilla `set.seed(2026)`)
* **Unidad de observación (grano):** Artículo periodístico individual seleccionado para revisión humana.
* **Propósito y uso:** Instrumento de control de calidad (*human-in-the-loop*) diseñado para auditar manualmente la precisión de las reglas de clasificación temática `delito_sdscj` / `modalidad_dai` sobre una muestra estratificada de artículos.
* **Linaje:** Generado por [`scripts/02_procesamiento/03_noticias/procesamiento_noticias.R`](../../scripts/02_procesamiento/03_noticias/procesamiento_noticias.R).

> **Sobre las columnas nulas:** `validacion_correcta` y `categoria_correcta` tienen **`195 NA`** de manera intencional porque se exportan como plantillas en blanco para ser diligenciadas por el evaluador durante la auditoría manual.

```r
muestra_val <- readr::read_csv(
  here::here("output", "tables", "muestra_validacion_manual_dai.csv"),
  show_col_types = FALSE
)
```

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `localidad` | `character` | No nula (`0 NA`) | `19` localidades urbanas | Localidad asignada a la noticia muestreada. |
| `año` | `numeric` | No nula (`0 NA`) | `[2022, 2026]` (`5` únicos) | Año de publicación del artículo. |
| `titulo` | `character` | No nula (`0 NA`) | `195` titulares únicos | Titular completo de la noticia a validar. |
| `resumen` | `character` | No nula (`0 NA`) | `192` resúmenes únicos | Extracto textual de soporte para la lectura rápida del revisor. |
| `delito_alto_impacto` | `character` | No nula (`0 NA`) | `13` categorías representadas | Etiqueta original proveniente del scraping. |
| `delito_sdscj` | `character` | No nula (`0 NA`) | `13` clases DAI + `"No DAI"` | Clasificación asignada automáticamente que se somete a validación. |
| `modalidad_dai` | `character` | No nula (`0 NA`) | `19` subcategorías muestreadas | Modalidad granular asignada por las reglas jerárquicas. |
| `campo_clasificacion` | `character` | No nula (`0 NA`) | `"titulo"`, `"resumen"`, `"cuerpo"` | Campo donde se activó la regla de clasificación. |
| `validacion_correcta` | `logical` | Totalmente nula (`195 NA`) | Intencionalmente vacío (`NA`) | Columna reservada para registrar `TRUE`/`FALSE` (o `1`/`0`) sobre si la clasificación es correcta. |
| `categoria_correcta` | `logical` | Totalmente nula (`195 NA`) | Intencionalmente vacío (`NA`) | Columna reservada para anotar la categoría corregida en caso de desacuerdo (leída como `logical` por estar vacía). |

---

## 6. `tabla_sensibilidad_escalamientos_pca.csv`

* **Ruta relativa:** `output/tables/tabla_sensibilidad_escalamientos_pca.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `5` filas × `8` columnas
* **Unidad de observación (grano):** Receta de preprocesamiento / representación espacial para $K = 3$.
* **Llave primaria (`PK`):** `espacio`
* **Propósito y uso:** Audita la estabilidad de la partición $K$-means ($K^* = 3$) frente a cinco transformaciones de escala (`Z-score (base)`, `Min-Max [0, 1]`, `Robusto (Mediana / IQR)`, `Log(1 + x) + Z-score` y `PCA (PC1 + PC2 = 96,9% var)`), comparando silueta media, inercia intra-clúster, Adjusted Rand Index (`ari_vs_base`) y varianza explicada por las dos primeras componentes principales. Cada `silueta_media` y `wss` se mide dentro de la matriz de distancias propia del escalamiento evaluado; por eso `Min-Max [0, 1]` (`0,5614`) y `PCA 2D` (`0,5539`) arrojan siluetas numéricamente mayores aun asignando exactamente las mismas `19` localidades que `Z-score` (`ari_vs_base = 1,0000`), manteniéndose `Z-score` por interpretabilidad directa sin pérdida de `PC3` (`3,11 %`) ni dependencia de extremos muestrales.
* **Linaje:** Generado por [`scripts/04_clustering_kmeans.R`](../../scripts/04_clustering_kmeans.R); consumido por la Sección 3 de [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `espacio` | `character` | No nula (`0 NA`) | `5` especificaciones de preprocesamiento | Nombre de la transformación evaluada sobre las 3 tasas de hurto. |
| `silueta_media` | `numeric` | No nula (`0 NA`) | `[0,4442, 0,5614]` (`base = 0,5211`) | Coeficiente promedio de silueta obtenido en ese espacio. |
| `n_silueta_neg` | `numeric` | No nula (`0 NA`) | `[0, 1]` (`base = 0`) | Cantidad de localidades con silueta negativa ($S_i < 0$). |
| `wss` | `numeric` | No nula (`0 NA`) | `[1,0106, 15,5923]` (`base = 13,6532`) | Suma total de cuadrados intra-clúster en la escala respectiva. |
| `ari_vs_base` | `numeric` | No nula (`0 NA`) | `[0,3380, 1]` | Índice de Rand Ajustado respecto al modelo base `Z-score`. |
| `pca_var_pc1` | `numeric` | No nula (`0 NA`) | `0,7331` | Proporción de varianza explicada por la componente principal 1. |
| `pca_var_pc2` | `numeric` | No nula (`0 NA`) | `0,2358` | Proporción de varianza explicada por la componente principal 2. |
| `pca_var_acum_2d` | `numeric` | No nula (`0 NA`) | `0,9689` | Varianza acumulada capturada en 2 dimensiones (`PC1 + PC2`). |

---

## 7. `tabla_comparacion_modelos_distancias.csv`

* **Ruta relativa:** `output/tables/tabla_comparacion_modelos_distancias.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `6` filas × `7` columnas
* **Unidad de observación (grano):** Combinación `Modelo × Métrica de distancia` ($K = 3$).
* **Llave primaria compuesta (`PK`):** `(modelo, distancia)`
* **Propósito y uso:** Contrasta la solución base de K-Means Euclidiano frente a clustering particional por medoides (`PAM`), clustering jerárquico aglomerativo (`AGNES` con enlace `Ward.D2`) bajo distancias Euclidiana y Manhattan, y Modelos de Mezclas Gaussianas (`GMM` con algoritmo EM / Mahalanobis).
* **Linaje:** Generado por [`scripts/04_clustering_kmeans.R`](../../scripts/04_clustering_kmeans.R); consumido por la Sección 3 de [`notebook/metodologia/02_modelado_clustering_sentometrics.qmd`](../../notebook/metodologia/02_modelado_clustering_sentometrics.qmd).

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `modelo` | `character` | No nula (`0 NA`) | `4` familias (`K-Means (base)`, `PAM (Medoides)`, `AGNES (Ward.D2)`, `GMM (Mezcla Gauss.)`) | Algoritmo de agrupamiento evaluado. |
| `distancia` | `character` | No nula (`0 NA`) | `"Euclidiana"`, `"Manhattan"`, `"Mahalanobis / EM"` | Métrica de disimilaridad empleada. |
| `silueta_media` | `numeric` | No nula (`0 NA`) | `[0,4099, 0,5398]` (`K-Means = 0,5211`) | Coeficiente de silueta medio en el espacio Z-score base. |
| `n_silueta_neg` | `numeric` | No nula (`0 NA`) | `[0, 1]` (`K-Means = 0`) | Número de localidades con silueta negativa. |
| `tamanios_grupo` | `character` | No nula (`0 NA`) | `"13 / 5 / 1"`, `"11 / 7 / 1"`, `"11 / 5 / 3"` | Conteo ordenado de localidades asignadas a cada uno de los 3 grupos. |
| `ari_vs_kmeans` | `numeric` | No nula (`0 NA`) | `[0,6269, 1]` | Concordia (Adjusted Rand Index) frente a la partición base K-Means. |
| `gap_k3` | `numeric` | No nula (`0 NA`) | `0,1256` | Estadístico *Gap* en $K = 3$ obtenido sobre la matriz estandarizada. |

---

## 8. `tabla_asignaciones_modelos_localidad.csv`

* **Ruta relativa:** `output/tables/tabla_asignaciones_modelos_localidad.csv`
* **Formato / Clase al leer con `readr`:** CSV UTF-8 (`spec_tbl_df`, `data.frame`)
* **Dimensiones verificadas:** `19` filas × `11` columnas
* **Unidad de observación (grano):** Localidad urbana de Bogotá D.C. (`19` localidades).
* **Llave primaria (`PK`):** `codigo_localidad`
* **Propósito y uso:** Tabla de concordancia territorio por territorio que registra el identificador de clúster asignado a cada localidad en siete especificaciones distintas (`kmeans_base`, `pca2_kmeans`, `pam_euclidiana`, `pam_manhattan`, `agnes_euclidiana`, `agnes_manhattan`, `gmm_3`), junto con el nombre final del clúster y la silueta individual del modelo elegido.
* **Linaje:** Generado por [`scripts/04_clustering_kmeans.R`](../../scripts/04_clustering_kmeans.R).

| Campo | Tipo (`readr`) | Nulabilidad | Dominio / Valores observados | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `codigo_localidad` | `character` | No nula (`0 NA`) | `"01"`..`"19"` (`19` únicos) | Código oficial de la localidad (con cero a la izquierda). |
| `localidad` | `character` | No nula (`0 NA`) | `19` nombres oficiales | Nombre normalizado de la localidad urbana. |
| `kmeans_base` | `numeric` | No nula (`0 NA`) | `{1, 2, 3}` | Etiqueta de grupo en K-Means Euclidiano base (`Z-score`). |
| `pca2_kmeans` | `numeric` | No nula (`0 NA`) | `{1, 2, 3}` | Etiqueta en K-Means sobre componentes principales (`PC1` y `PC2`). |
| `pam_euclidiana` | `numeric` | No nula (`0 NA`) | `{1, 2, 3}` | Etiqueta en PAM con distancia Euclidiana. |
| `pam_manhattan` | `numeric` | No nula (`0 NA`) | `{1, 2, 3}` | Etiqueta en PAM con distancia Manhattan ($L_1$). |
| `agnes_euclidiana` | `numeric` | No nula (`0 NA`) | `{1, 2, 3}` | Etiqueta en AGNES (`Ward.D2`) con distancia Euclidiana. |
| `agnes_manhattan` | `numeric` | No nula (`0 NA`) | `{1, 2, 3}` | Etiqueta en AGNES (`Ward.D2`) con distancia Manhattan. |
| `gmm_3` | `numeric` | No nula (`0 NA`) | `{1, 2, 3}` | Etiqueta en Modelo de Mezclas Gaussianas ($G = 3$). |
| `cluster_nombre` | `character` | No nula (`0 NA`) | `3` perfiles territoriales | Etiqueta semántica del clúster final elegido. |
| `silueta_localidad` | `numeric` | No nula (`0 NA`) | `[0,0000, 0,7176]` (`0` negativas) | Coeficiente de silueta individual de la localidad en el modelo final. |

---

> ⬅️ Volver al [índice del diccionario](./README.md) | Ir al [README principal](../../README.md)
