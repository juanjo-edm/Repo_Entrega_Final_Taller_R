# Hurtos y sentimiento mediático en Bogotá
**Propuesta académica | Datos abiertos + sentometrics + K-means + Shiny**

---

## 1. Pregunta de investigación e hipótesis

¿Cómo se relacionan los niveles de hurtos registrados y el tono de las noticias sobre inseguridad en las 19 localidades urbanas de Bogotá? Se estudiarán los hurtos a personas, residencias y motocicletas mediante tasas por 100.000 habitantes; se construirán perfiles territoriales con K-means y se cuantificará el sentimiento de las noticias mediante `sentometrics`. La hipótesis exploratoria es que las localidades con tasas más altas de hurto presentan una cobertura más frecuente y negativa. El estudio será descriptivo: no atribuirá causalidad ni confundirá la cobertura periodística con la percepción ciudadana.

---

## 2. Motivación

Los delitos contra el patrimonio afectan la seguridad urbana y las decisiones de movilidad, consumo y uso de espacios públicos. No obstante, el volumen de hechos denunciados y su representación en las noticias no necesariamente evolucionan juntos. Contrastar registros oficiales con el tono de la cobertura mediática permite reconocer coincidencias, divergencias y diferencias territoriales con evidencia reproducible. El estudio se enfocará en una interpretación descriptiva útil para la discusión social y económica sobre seguridad en Bogotá, sin confundir cobertura informativa, criminalidad registrada y opinión ciudadana.

---

## 3. Datos abiertos, fuentes, periodo y relación entre bases

Se combinarán cuatro fuentes públicas: registros oficiales de delitos, proyecciones de población, noticias de Google News y límites administrativos de las localidades. El recorrido del análisis será: hurtos oficiales → tasas → K-means; titulares y resúmenes de noticias → sentometrics; comparación por localidad y año → Shiny.

| Fuente oficial / acceso | Contenido y unidad inicial | Uso y periodicidad |
| :--- | :--- | :--- |
| **A. Secretaría Distrital de Seguridad — “Delito de Alto Impacto. Bogotá D.C.”** Datos Abiertos Bogotá / SIEDCO | Conteos de hurtos a personas, residencias y motocicletas por localidad; campos por año en el recurso geográfico publicado. | Criminalidad registrada; LOCALIDAD × AÑO. Actualización declarada mensual del recurso, no necesariamente una serie mensual. |
| **B. Secretaría Distrital de Salud — proyecciones de población 2005–2035**; Datos Abiertos Bogotá. | Proyección de habitantes por localidad y año; archivo CSV. | Denominador para calcular tasas de delitos por 100.000 habitantes. |
| **C. Google News — consulta pública por RSS**; no se usarán matrices Excel como fuente primaria. | Una noticia recuperada: fecha, medio, título, resumen disponible, URL y localidad consultada. El texto disponible es la entrada de sentometrics. | Corpus mediático. Puntuación y proporción de noticias negativas; agregación por localidad y año cuando exista cobertura. |
| **D. Secretaría Distrital de Planeación — “Localidad. Bogotá D.C.”** | Polígonos oficiales y nombre/código de localidad (GeoJSON/SHP). | Geografía para mapa interactivo en la Shiny App. |

**Cobertura objetivo:** 01/01/2022–31/12/2025, cuatro años calendario completos, 19 localidades urbanas (se excluye Sumapaz). Las noticias del mismo intervalo solo se incluirán si las consultas públicas ofrecen registros recuperables y auditables. No se asumirá disponibilidad histórica completa del RSS. El número final de noticias y celdas válidas se reportará tras la descarga real.

---

## 4. Construcción de datos y metodología

Se descargarán los datos oficiales de hurtos y población mediante fuentes públicas; las noticias se obtendrán con consultas RSS de Google News por localidad y palabras clave. Se normalizarán fechas y localidades, se eliminarán duplicados y se documentarán faltantes. `sentometrics` analizará títulos y resúmenes con un léxico de polaridad en español documentado y validado; producirá una puntuación por noticia y medidas de sentimiento por periodo. K-means agrupará localidades usando exclusivamente las tres tasas oficiales de hurtos estandarizadas ($K = 2–4$; selección mediante silueta). Se compararán los perfiles de hurto con la frecuencia y negatividad de la cobertura, sin interpretar asociaciones como efectos causales.

### 4.1. Indicadores, unidades y llaves de vinculación

| Base | Variables relevantes | Llave de vinculación |
| :--- | :--- | :--- |
| **Delitos (oficial)** | `localidad`, `año`, conteo por tipo de hurto; tasa por 100.000 habitantes tras unir población. | Código/nombre estandarizado de localidad + año. |
| **Población (oficial)** | `localidad`, `año`, población proyectada total. | Localidad + año. |
| **Noticias (Google News)** | `id`, `fecha`, `medio`, `título`, `resumen`, `url`, `localidad`, puntuación `sentometrics`, indicador de sentimiento negativo. | Localidad + año para comparación; mes se conserva para EDA. |
| **Geografía (oficial)** | `código de localidad`, `geometría`. | Código de localidad para el mapa. |

### 4.2. sentometrics: análisis de sentimiento mediático

* **Entrada:** titulares y resúmenes de noticias disponibles en español, con fecha, medio y localidad verificada. En R se construirá el corpus fechado (`sento_corpus`), se incorporará el NRC Emotion Lexicon en español, utilizando únicamente sus categorías de polaridad positiva y negativa (`sento_lexicons`), y se obtendrá un puntaje proporcional por noticia (`compute_sentiment`). Los indicadores serán número de noticias, sentimiento medio y porcentaje de noticias negativas por localidad y año. Se verificará la cobertura del vocabulario y se revisará manualmente una muestra de titulares: la falta de palabras reconocidas no implica neutralidad. Se citará el léxico y su licencia para investigación académica.
* **Comparación principal:** LOCALIDAD × AÑO, porque el recurso oficial de delitos publica conteos por año. Las noticias solo se atribuirán territorialmente cuando el contenido permita confirmar la localidad; los textos ambiguos se conservarán a nivel Bogotá. El periodo objetivo 2022–2025 depende de los registros públicos recuperables: Google News RSS no garantiza un archivo histórico completo. En la semana 11 se fijará el periodo común observado. Las fechas mensuales se preservarán para explorar la prensa sin confundir ausencia de registros recuperados con cero noticias.

### 4.3. Exploración descriptiva obligatoria

* **Análisis descriptivo:** conteos y tasas de hurto por modalidad, localidad y año; distribución de población; número de noticias por periodo y fuente, porcentaje de duplicados, cobertura del léxico y distribución de las puntuaciones de `sentometrics`. La primera entrega contendrá al menos dos gráficos calculados: (1) comparación de tasas oficiales de hurto por localidad y modalidad y (2) evolución del sentimiento medio de las noticias en el periodo efectivamente disponible, acompañada del número de textos analizados. Se añadirán interpretaciones conectadas con la hipótesis; la versión final incorporará clusters y mapa interactivo.

> **Alcance:** Los registros oficiales reflejan hurtos registrados; `sentometrics` cuantifica la polaridad de textos noticiosos disponibles, no opiniones de la ciudadanía. Los resultados dependerán de la cobertura temporal del RSS y de la adecuación del léxico español. Ninguna asociación será interpretada como causalidad.

---

## 5. Productos, tiempos y compromisos de entrega

El cronograma de trabajo cuenta con fechas límite exactas orientadas al cierre definitivo el **17 de noviembre de 2026**. Entre la primera entrega y la entrega final existe un intervalo de un mes con seguimiento continuo por hitos.

| Momento | Qué se entregará (contenido verificable) | Plazo límite |
| :--- | :--- | :--- |
| **Primera entrega — propuesta y EDA** | Documento de máximo 3 páginas, con pregunta/hipótesis, motivación, fuentes y variables, metodología, estadísticas calculadas y al menos dos gráficos reales con narrativa (*storytelling*). Incluir prueba inicial de `sentometrics` en el corpus recuperado, revisión del léxico español y delimitación documentada de la ventana temporal. Primeros cuatro apartados: máximo 150 palabras cada uno; EDA/storytelling: máximo 700 palabras. | **20 de octubre de 2026** (Semana 11)<br>Cierre de auditoría de fuentes y radicación en Bloque Neón. |
| **Presentación y sustentación** | Presentación de 20 minutos en clase: resumen ejecutivo, pregunta, motivación, datos, metodología, descriptivos, clustering, sentometrics y hallazgos clave. | **17 de noviembre de 2026** (Semana 16)<br>Sustentación presencial en clase y co-evaluación. |
| **Entrega final — informe + scripts + aplicación** | Informe de máximo 5 páginas (anexos aparte), con introducción, datos/EDA, metodología, resultados e interpretación, referencias; scripts comentados y ejecutables con `master.R`; y Shiny con mapa de hurtos, series de sentimiento `sentometrics`, perfiles K-means, filtros por localidad/año y tabla de noticias. | **17 de noviembre de 2026** (Semana 16)<br>Aplicación desplegada, repositorio y resultados verificados. |

### 5.1. Secuencia de trabajo entre entregas

* **20 de octubre (Hito 1):** Descargas auditadas de hurtos, población y prensa; prueba de corpus español y sentometrics; descriptivos reales, $\ge 2$ gráficos y storytelling; confirmación del periodo de coincidencia y radicación del informe preliminar.
* **27 de octubre (Hito 2):** Tasas de hurto por 100.000 habitantes, tablas intermedias en `data/processed/`, configuración de ponderaciones intra-mes y decaimiento exponencial en `sentometrics`.
* **3 de noviembre (Hito 3):** Primeros modelos de clustering K-means y PCA validados, y esqueleto funcional del tablero Shiny con navegación por tarjetas en `bslib`.
* **10 de noviembre (Hito 4):** Shiny interactiva con mapas coropléticos en `leaflet`, evolución temporal del sentimiento mediático por localidad y cruce con perfiles de delincuencia.
* **14 de noviembre (Hito 5):** Versión candidata probada de punta a punta, reporte de metodología, verificación de scripts de reproducción con `master.R` y ensayos de exposición.
* **17 de noviembre (Hito 6 — Cierre final):** Despliegue de la app Shiny en Posit Connect / shinyapps.io, entrega de informe académico final de 5 páginas y sustentación del proyecto en clase.

---

## 5.2. Fuentes y referencias consultables

* **Datos delictivos (SDSCJ):** [https://datosabiertos.bogota.gov.co/dataset/delito-de-alto-impacto-bogota-d-c](https://datosabiertos.bogota.gov.co/dataset/delito-de-alto-impacto-bogota-d-c)
* **Población (SDS):** [https://datosabiertos.bogota.gov.co/dataset/piramide-poblacional-bogota-d-c](https://datosabiertos.bogota.gov.co/dataset/piramide-poblacional-bogota-d-c)
* **Límites de localidades (SDP):** [https://datosabiertos.bogota.gov.co/dataset/localidad-bogota-d-c](https://datosabiertos.bogota.gov.co/dataset/localidad-bogota-d-c)
* **Noticias (feed RSS):** [https://news.google.com/rss/search](https://news.google.com/rss/search)
* **Consulta complementaria SIEDCO:** [https://www.scj.gov.co/transparencia/obligacion-reporte-informacion/preguntas-frecuentes?page=3](https://www.scj.gov.co/transparencia/obligacion-reporte-informacion/preguntas-frecuentes?page=3)
* **Método:** Ardia, D., Bluteau, K., Borms, S. y Boudt, K. (2021). *The R Package sentometrics to Compute, Aggregate and Predict with Textual Sentiment*. Journal of Statistical Software, 99(2). DOI: [10.18637/jss.v099.i02](https://doi.org/10.18637/jss.v099.i02). Documentación: [https://sentometrics-research.com/sentometrics/](https://sentometrics-research.com/sentometrics/)
* **Léxico español (NRC):** [https://www.nrc.canada.ca/en/research-development/products-services/technical-advisory-services/sentiment-emotion-lexicons](https://www.nrc.canada.ca/en/research-development/products-services/technical-advisory-services/sentiment-emotion-lexicons)
