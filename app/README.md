# Aplicación Interactiva en R Shiny (`app/`)

En esta carpeta se aloja el tablero interactivo construido con [`bslib`](https://rstudio.github.io/bslib/) (Bootstrap 5), [`plotly`](https://plotly.com/r/), [`leaflet`](https://rstudio.github.io/leaflet/) y [`DT`](https://rstudio.github.io/DT/) que integra los resultados de criminalidad territorial ($K$-Means) y el análisis cuantitativo de sentimiento mediático (`sentometrics`).

---

## 1. Arquitectura de las 5 Pestañas (`page_navbar`)

1. **Panorama Territorial y Clústeres ($K$-Means):**
   * **Tarjetas KPI (`value_box`):** Tasa media distrital según modalidad seleccionada, localidad más crítica, sentimiento mediático promedio y porcentaje de noticias negativas.
   * **Mapa Coroplético Interactivo (`leaflet`):** Permite colorear las 19 localidades urbanas por **Clúster $K$-Means ($K^* = 3$)**, **Tasa de Hurto (personas, residencias, motos, total)** o **Sentimiento Mediático**, con *popups* detallados por localidad.
   * **Contraste Realidad vs. Prensa (`plotly` y `DT`):** Dispersión interactiva entre tasas oficiales por 100.000 habitantes e índice de sentimiento, ranking territorial y tabla de perfiles centroides.
2. **Series de Sentimiento (`T-16` — `sento_measures` y `peakdates`):**
   * Exploración interactiva de las **364 series mensuales** (`06_measures_long.rds`) agrupadas por **Clústeres Territoriales (3)**, **Tópicos/Modalidades DAI (4)** o **Localidades (19)**, permitiendo alternar entre los diccionarios `crimen_es` y `nrc_es` y los 7 esquemas de suavizamiento temporal (`linear`, `exponential`, `beta` con `lag = 6` meses).
   * Visualización del **Índice Global Ponderado de Bogotá** (`07_global_index.rds`) y tabla de meses históricos críticos detectados con `peakdates()`.
3. **Impacto y Atribuciones (`T-18` — `sento_model` Elastic Net y `attributions`):**
   * Indicadores de desempeño de la regresión penalizada Elastic Net ($\alpha = 0.2$, selección BIC, $R^2 = 87.5\%$, horizonte $h = 1$ mes).
   * Gráfico de barras apiladas mensuales (`plot.attributions`) que descompone el aporte marginal por **Características (`features`)**, **Léxicos (`lexicons`)** y **Memoria Temporal (`time`)**, en escala bruta o normalizada `[-1, 1]`.
   * Comparativa entre la serie delictiva observada ($y_t$) y predicha ($\hat{y}_t$) y ranking de los 15 predictores activos con mayor coeficiente $|\hat{\beta}|$.
4. **Noticias Críticas y Corpus (`T-08` y `T-12` — `peakdocs` y `corpus_summarize`):**
   * **Explorador de Noticias Críticas (`peakdocs`):** Tabla interactiva `DT` filtrable por tipo de pico (picos globales/locales, más negativas, más positivas, o las 3.916 noticias), localidad, categoría oficial de los 11 Delitos de Alto Impacto (SDSCJ) y rango de años, con enlace directo a cada artículo.
   * **Evolución del Corpus (`corpus_summarize`):** Gráficos de volumen mensual de documentos y tokens, distribución por modalidad DAI y términos de mayor valencia del léxico `crimen_es`.
5. **Metodología y Contratos (`T-01` a `T-04`, `T-20`):**
   * Síntesis matemática en $\LaTeX$ (`MathJax`) de la ponderación tridimensional ($\omega, \theta, b$), modificadores de valencia, modelo Elastic Net y diccionario de los 8 artefactos `.rds`.

---

## 2. Cómo Ejecutar la Aplicación

Desde la raíz del proyecto en R / RStudio:
```r
# 1. (Opcional) Si deseas regenerar todos los datos desde cero (~25 segundos):
source(here::here("scripts", "master.R"))

# 2. Iniciar la aplicación interactiva:
shiny::runApp(here::here("app"))
```
