# Aplicación Interactiva R Shiny (`app/`) — "Bogo-Atrack"

**Proyecto:** Hurtos y sentimiento mediático en Bogotá (2022–2026)  
**Subtítulo en tablero:** *Observatorio de hurto y sentimiento mediático*  
**Programa:** Maestría en Economía Aplicada (MECA) — *Taller de Programación en R*  
**Autores:** Olga Lucía Ramírez, Juan José Echeverry, Sergio López, Miguelangel Palma, Gabriel Echeverry, Juan Esteban Carvajal (Grupo 10)  

---

## Propósito y Diseño Visual

Esta carpeta contiene la aplicación interactiva **R Shiny** (**"Bogo-Atrack"** · *Observatorio de hurto y sentimiento mediático*), construida con `{bslib}` (Bootstrap 5 en tema oscuro `#0E1116`), `{leaflet}` (OpenStreetMap con filtro oscuro libre de API key), `{plotly}` y `{DT}`.

La interfaz contrasta dos lecturas de la seguridad urbana en las 19 localidades de Bogotá:
- **Ámbar (`#F0A43A`)**: lo que dicen las **denuncias oficiales** (tasas de hurto por 100.000 habitantes de la SDSCJ / SIEDCO y proyecciones poblacionales SDS).
- **Azul (`#79AEFF`)**: lo que dice la **prensa digital** (polaridad y cobertura calculadas con `sentometrics`).

---

## Estructura de la Carpeta

```text
app/
├── README.md        # Documentación de arquitectura y guía de ejecución
├── app.R            # Aplicación Shiny completa ("Bogo-Atrack")
└── www/             # Recursos estáticos (hoja de estilos custom.css)
```

---

## Arquitectura de Datos (Desacoplamiento Eficiente)

La aplicación **no ejecuta procesos pesados de scraping ni recalcula matrices léxicas** en tiempo de ejecución. Toda la reactividad lee el paquete pre-computado en una sola llamada `readRDS()` al iniciar:

- `data/processed/datos_consolidados_shiny.rds` (generado por `scripts/05_export_insumos_shiny.R` e integrado en `scripts/master.R`).
- Los objetos globales (`datos_promedio_global`, `measures_long`, `attr_long_raw`, `attr_long_norm`, `ajuste_temporal`, `coeficientes_df`, `metricas_modelo`) se pre-calculan fuera de `server` y los reactivos de consulta usan `bindCache()` para respuesta instantánea.

---

## Las 6 Pestañas del Tablero (`page_navbar`)

1. **`Panorama`**:
   - Filtros por modalidad de hurto (*Total*, *Personas*, *Residencias*, *Motocicletas*), año (*Promedio 2022–2026* o año específico) y capa del mapa (*Denuncias* en ámbar vs. *Prensa* en azul). Al elegir una modalidad específica distinta de *Total*, tanto las denuncias como las métricas de prensa (*noticias*, *sentimiento medio* y *% negativas*) se filtran dinámicamente para esa modalidad.
   - 4 tarjetas KPI (`value_box`), mapa coroplético interactivo en `{leaflet}` (con clic directo para saltar a la ficha de la localidad) y ranking Top 5 sincronizado con la capa y paleta activas (tasas en ámbar o prensa en azul).
2. **`Mi localidad`**:
   - Ficha individual de cualquiera de las 19 localidades urbanas con su puesto en el ranking distrital, 4 tarjetas KPI por modalidad (*Hurto total*, *Hurto a personas*, *Hurto a residencias* y *Hurto de motocicletas*), evolución anual comparada frente al promedio de Bogotá (filtrable por las 4 modalidades), composición del tono de prensa por año y tabla interactiva (`{DT}`) con las 5 noticias más negativas y las 5 más positivas con enlaces directos.
3. **`Hurto vs. prensa`**:
   - Gráfico de dispersión interactivo (`{plotly}`) que cruza la tasa de hurto denunciado filtrable por modalidad (*Total*, *Personas*, *Residencias*, *Motocicletas*) en el eje X contra el porcentaje de noticias negativas en el eje Y (también actualizado dinámicamente según la modalidad seleccionada), dividido en cuatro cuadrantes interpretativos (*¿estigma mediático?*, *alta denuncia y prensa dura*, etc.) con selección por clic (`plotly_click`).
4. **`Clusters`**:
   - Cartografía (`{leaflet}`) y tarjetas comparativas (incluyendo tasa total y desagregada por modalidad) de los 3 grupos territoriales hallados con K-Means ($K^* = 3$): *Céntrico e Institucional* (`#B08CF0`), *Comercial y Automotor* (`#E86A50`) y *Residencial y Periférico* (`#3FB8A6`).
   - Tarjeta expandible (`full_screen = TRUE`) con el **gráfico tridimensional interactivo (`{plotly}` `scatter3d`)** de las 19 localidades, radios intra-clúster y centroides $\mu_k$: incluye controles `bslib::input_switch()` para mostrar u ocultar nombres y alternar entre tasas por 100.000 habitantes y $Z$-scores estandarizados, más sincronización bidireccional al hacer clic en esferas, mapa o tarjetas.
5. **`Sentometrics y Elastic Net`**:
   - Indicadores de desempeño del modelo regularizado Elastic Net ($\text{BIC}$, $h = 1$ mes: $R^2$, $\alpha^*$, $\lambda^*$, series activas y $\text{RMSE}$), ajustado sobre las **993 noticias objetivo** de las 3 modalidades SIEDCO (*Hurto a personas*, *Hurto a residencias* y *Hurto de motocicletas*).
   - Explorador interactivo de las **36 series mensuales de sentimiento** (`sento_measures`, `2 léxicos × 6 covariables binarias × 3 curvas temporales`) por grupo de *features* (`Clúster Territorial` o `Modalidad de Hurto`), léxico (`crimen_es` vs. `nrc_es`) y esquema de memoria temporal (`lag = 6` meses: `linear`, `exponential0.5`, `beta22`), incluyendo las fechas críticas detectadas con `peakdates()`.
   - Descomposición aditiva de **atribuciones** (`attributions()`) por clúster, modalidad de hurto, léxico y memoria temporal frente a la tasa mensual observada de `SIEDCO.csv` ($\hat{y}_{t+1}$ vs. $y_{t+1}$), junto con el ranking de los 10 coeficientes $|\beta|$ de mayor magnitud.
6. **`Datos y método`**:
   - Síntesis de fuentes oficiales (`SIEDCO.csv` + proyecciones SDS + corpus de 993 notas objetivo sobre 3.916 recopiladas), advertencias metodológicas (corte septiembre 2026 y efecto de población flotante en el centro) y tabla interactiva con el contrato de los 2 artefactos `.rds` del pipeline (`sentometrics_pipeline.rds` y `datos_consolidados_shiny.rds`).

---

## Cómo Ejecutar la Aplicación Localmente

Desde la consola de R o RStudio (con el proyecto abierto en la raíz del repositorio):

```r
# 1. (Opcional) Si aún no existe datos_consolidados_shiny.rds, correr el pipeline maestro:
source(here::here("scripts", "master.R"))

# 2. Lanzar la aplicación interactiva:
shiny::runApp(here::here("app"))
```
