# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: app/app.R
# ROL: Tablero Interactivo R Shiny (bslib Bootstrap 5 — Tareas T-08 a T-19)
# AUTORES: Juan José Echeverry, Olga Lucía Ramírez, Sergio López,
#          Miguelangel Palma, Gabriel Echeverry, Juan Esteban Carvajal (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

library(shiny)
library(bslib)
library(here)
library(conflicted)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(scales)
library(plotly)
library(DT)
library(leaflet)
library(sf)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("layout", "plotly", quiet = TRUE)

# 2. Carga de Insumos Consolidados ----

ruta_bundle <- here::here("data", "processed", "datos_consolidados_shiny.rds")
if (!file.exists(ruta_bundle)) {
  stop(
    "No se encontró 'data/processed/datos_consolidados_shiny.rds'. ",
    "Ejecute primero: source(here::here('scripts', 'master.R'))"
  )
}

datos_app         <- readRDS(ruta_bundle)
panel_localidades <- as_tibble(datos_app$panel_localidades)
clusters_perfiles <- as_tibble(datos_app$clusters_perfiles)
geo_localidades   <- datos_app$geometrias
corpus_stats_mes  <- as_tibble(datos_app$corpus_stats_mes)
corpus_stats_anio <- as_tibble(datos_app$corpus_stats_anio)
lexicos_info      <- datos_app$lexicos_info
tabla_noticias    <- as_tibble(datos_app$peak_docs$tabla_completa)
measures_long     <- as_tibble(datos_app$measures_long)
global_index_df   <- as_tibble(datos_app$global_index$serie_global)
peakdates_neg     <- datos_app$global_index$peakdates_neg
peakdates_pos     <- datos_app$global_index$peakdates_pos
attr_long_raw     <- as_tibble(datos_app$attributions$attr_long_raw)
attr_long_norm    <- as_tibble(datos_app$attributions$attr_long_norm)
ajuste_temporal   <- as_tibble(datos_app$attributions$ajuste_temporal)
coeficientes_df   <- as_tibble(datos_app$attributions$coeficientes)
metricas_modelo   <- datos_app$attributions$metricas_modelo

# Paletas y diccionarios visuales
colores_cluster <- c(
  "Céntrico e Institucional" = "#c0392b",
  "Comercial y Automotor"    = "#e67e22",
  "Residencial y Periférico" = "#27ae60"
)

catalogo_tasas <- c(
  "Tasa de Hurto Total (por 100k hab.)"        = "tasa_hurto_total",
  "Tasa de Hurto a Personas (por 100k hab.)"   = "tasa_hurto_personas",
  "Tasa de Hurto a Residencias (por 100k hab.)" = "tasa_hurto_residencias",
  "Tasa de Hurto a Motocicletas (por 100k hab.)" = "tasa_hurto_motos"
)

lista_localidades <- sort(unique(panel_localidades$localidad))
lista_clusters    <- c(
  "Céntrico e Institucional",
  "Comercial y Automotor",
  "Residencial y Periférico"
)
lista_esquemas_tiempo <- sort(unique(measures_long$time))
names(lista_esquemas_tiempo) <- case_when(
  lista_esquemas_tiempo == "linear"         ~ "Lineal (memoria uniforme gradual)",
  lista_esquemas_tiempo == "exponential0.2" ~ "Exponencial (alpha = 0.2, memoria persistente)",
  lista_esquemas_tiempo == "exponential0.5" ~ "Exponencial (alpha = 0.5, decaimiento rápido)",
  lista_esquemas_tiempo == "beta11"         ~ "Beta (a = 1, b = 1 — uniforme)",
  lista_esquemas_tiempo == "beta12"         ~ "Beta (a = 1, b = 2 — sesgo reciente)",
  lista_esquemas_tiempo == "beta13"         ~ "Beta (a = 1, b = 3 — alta ponderación reciente)",
  lista_esquemas_tiempo == "beta22"         ~ "Beta (a = 2, b = 2 — pico intermedio)",
  lista_esquemas_tiempo == "beta23"         ~ "Beta (a = 2, b = 3 — pico retardado)",
  TRUE                                      ~ lista_esquemas_tiempo
)

# 3. Interfaz de Usuario (UI con bslib Bootstrap 5) ----

tema_meca <- bs_theme(
  version    = 5,
  bootswatch = "flatly",
  primary    = "#1b365d",
  secondary  = "#2980b9",
  success    = "#27ae60",
  warning    = "#e67e22",
  danger     = "#c0392b"
)

ui <- page_navbar(
  title = span(
    icon("shield-halved"),
    "Hurtos y Sentimiento Mediático en Bogotá (2022–2026)"
  ),
  theme = tema_meca,
  fillable = FALSE,
  header = tags$head(
    includeCSS(here::here("app", "www", "custom.css")),
    withMathJax()
  ),

  # ============================================================================
  # PESTAÑA 1: PANORAMA TERRITORIAL Y CLÚSTERES K-MEANS
  # ============================================================================
  nav_panel(
    title = "1. Panorama Territorial y Clústeres",
    icon  = icon("map-location-dot"),
    layout_sidebar(
      sidebar = sidebar(
        title = "Filtros Territoriales",
        width = 300,
        selectInput(
          "anio_terr",
          "Periodo de análisis:",
          choices = c(
            "Promedio Multianual (2022–2026)" = "todos",
            "2022" = "2022",
            "2023" = "2023",
            "2024" = "2024",
            "2025" = "2025",
            "2026" = "2026"
          ),
          selected = "todos"
        ),
        selectInput(
          "metrica_hurto",
          "Modalidad delictiva (por 100k hab.):",
          choices  = catalogo_tasas,
          selected = "tasa_hurto_total"
        ),
        radioButtons(
          "capa_mapa",
          "Colorear mapa coroplético por:",
          choices = c(
            "Clúster K-Means (K* = 3)"       = "cluster",
            "Tasa de Hurto seleccionada"     = "tasa",
            "Sentimiento Mediático Promedio" = "sentimiento"
          ),
          selected = "cluster"
        ),
        checkboxGroupInput(
          "filtro_cluster_terr",
          "Filtrar perfiles territoriales:",
          choices  = lista_clusters,
          selected = lista_clusters
        ),
        hr(),
        helpText(
          icon("circle-info"),
          "Haz clic sobre cualquier localidad en el mapa para inspeccionar su ficha detallada."
        )
      ),

      # KPIs superiores
      layout_column_wrap(
        width = 1 / 4,
        fill  = FALSE,
        value_box(
          title    = "Tasa Media Seleccionada",
          value    = textOutput("kpi_tasa_media"),
          showcase = icon("scale-balanced"),
          theme    = "primary",
          p("Denuncias por cada 100.000 hab.")
        ),
        value_box(
          title    = "Localidad de Mayor Incidencia",
          value    = textOutput("kpi_loc_critica"),
          showcase = icon("triangle-exclamation"),
          theme    = "danger",
          p(textOutput("kpi_loc_critica_sub"))
        ),
        value_box(
          title    = "Sentimiento Mediático Promedio",
          value    = textOutput("kpi_sent_medio"),
          showcase = icon("newspaper"),
          theme    = "secondary",
          p("Índice neto sentometrics (NRC + Crimen)")
        ),
        value_box(
          title    = "Cobertura con Tono Negativo",
          value    = textOutput("kpi_prop_neg"),
          showcase = icon("chart-pie"),
          theme    = "warning",
          p(textOutput("kpi_total_noticias_sub"))
        )
      ),

      # Mapa y gráficos comparativos
      layout_columns(
        col_widths = c(6, 6),
        card(
          full_screen = TRUE,
          card_header(
            "Cartografía Interactiva de Bogotá (19 Localidades Urbanas)"
          ),
          leafletOutput("mapa_bogota", height = "520px")
        ),
        navset_card_underline(
          full_screen = TRUE,
          title = "Contraste Empírico: Denuncias vs. Prensa",
          nav_panel(
            "Realidad vs. Tono Mediático",
            plotlyOutput("plot_cruce_hurto_sent", height = "460px")
          ),
          nav_panel(
            "Ranking por Localidad",
            plotlyOutput("plot_ranking_localidades", height = "460px")
          ),
          nav_panel(
            "Perfiles K-Means (K* = 3)",
            DTOutput("tabla_perfiles_kmeans")
          )
        )
      )
    )
  ),

  # ============================================================================
  # PESTAÑA 2: SERIES DE SENTIMIENTO (T-13, T-14, T-15, T-16)
  # ============================================================================
  nav_panel(
    title = "2. Series de Sentimiento",
    icon  = icon("chart-line"),
    layout_sidebar(
      sidebar = sidebar(
        title = "Parámetros de Agregación (ctr_agg)",
        width = 320,
        selectInput(
          "grupo_serie",
          "1. Dimensión de agrupación (Features):",
          choices = c(
            "Clústeres Territoriales (K* = 3)" = "Clúster Territorial",
            "Tópicos y Modalidades DAI (4)"    = "Tópico / Modalidad DAI",
            "Localidades Individuales (19)"    = "Localidad"
          ),
          selected = "Clúster Territorial"
        ),
        uiOutput("ui_selector_features_serie"),
        selectInput(
          "lexico_serie",
          "3. Diccionario léxico (sento_lexicons):",
          choices = c(
            "Léxico Seguridad y Crimen Bogotá (crimen_es)" = "crimen_es",
            "Léxico General en Español (nrc_es)"           = "nrc_es"
          ),
          selected = "crimen_es"
        ),
        selectInput(
          "tiempo_serie",
          "4. Esquema de ponderación temporal (howTime, lag = 6m):",
          choices  = lista_esquemas_tiempo,
          selected = "exponential0.5"
        ),
        checkboxInput(
          "mostrar_peakdates",
          "Resaltar fechas pico de alarma (peakdates)",
          value = TRUE
        ),
        hr(),
        div(
          class = "small text-muted",
          strong("Especificación activa:"),
          br(),
          "• Intra-documento (ω): proportionalPol",
          br(),
          "• Entre documentos (θ): proportional",
          br(),
          "• Ventana móvil: lag = 6 meses"
        )
      ),

      card(
        full_screen = TRUE,
        card_header(
          "Evolución Mensual de las Series de Sentimiento (sento_measures: 2022–2026)"
        ),
        plotlyOutput("plot_series_measures", height = "430px")
      ),

      layout_columns(
        col_widths = c(7, 5),
        card(
          full_screen = TRUE,
          card_header(
            "Índice Global Ponderado de Sentimiento en Bogotá (aggregate do.global = TRUE)"
          ),
          plotlyOutput("plot_indice_global", height = "340px")
        ),
        card(
          full_screen = TRUE,
          card_header(
            "Fechas Críticas de Polaridad Detectadas (peakdates)"
          ),
          DTOutput("tabla_peakdates")
        )
      )
    )
  ),

  # ============================================================================
  # PESTAÑA 3: IMPACTO Y ATRIBUCIONES (T-17, T-18)
  # ============================================================================
  nav_panel(
    title = "3. Impacto y Atribuciones",
    icon  = icon("sliders"),
    layout_sidebar(
      sidebar = sidebar(
        title = "Modelo Elastic Net y Atribuciones",
        width = 310,
        selectInput(
          "dim_atribucion",
          "Dimensión de descomposición (attributions):",
          choices = c(
            "Por Características (Features)"      = "features",
            "Por Diccionarios Léxicos (Lexicons)" = "lexicons",
            "Por Memoria Temporal (Time)"         = "time"
          ),
          selected = "features"
        ),
        conditionalPanel(
          condition = "input.dim_atribucion == 'features'",
          selectInput(
            "subgrupo_attr_feat",
            "Subconjunto de features a visualizar:",
            choices = c(
              "Clústeres Territoriales (3)"   = "clusters",
              "Tópicos / Modalidades DAI (4)" = "temas",
              "Top 8 Localidades de Mayor Impacto" = "localidades"
            ),
            selected = "clusters"
          )
        ),
        radioButtons(
          "escala_atribucion",
          "Escala de las atribuciones:",
          choices = c(
            "En unidades de la variable objetivo (Bruta)" = "raw",
            "Normalizada en [-1, 1] (do.normalize = TRUE)" = "norm"
          ),
          selected = "raw"
        ),
        hr(),
        div(
          class = "small text-muted",
          strong("Parámetros de sento_model():"),
          br(),
          paste0("• Familia: Gaussian Elastic Net (h = ", metricas_modelo$horizonte_h, " mes)"),
          br(),
          paste0("• Criterio óptimo: ", metricas_modelo$criterio, " (α = ", metricas_modelo$alpha_optimo, ", λ = ", round(metricas_modelo$lambda_optimo, 3), ")"),
          br(),
          paste0("• Series candidatas: ", metricas_modelo$n_predictores, " | Activas: ", metricas_modelo$n_activos)
        )
      ),

      layout_column_wrap(
        width = 1 / 4,
        fill  = FALSE,
        value_box(
          title    = "Bondad de Ajuste (R²)",
          value    = scales::percent(metricas_modelo$r2_in_sample, accuracy = 0.1),
          showcase = icon("bullseye"),
          theme    = "success",
          p("Varianza mensual explicada (h = 1)")
        ),
        value_box(
          title    = "Hiperparámetro Elastic Net",
          value    = paste0("α = ", metricas_modelo$alpha_optimo, " | λ = ", round(metricas_modelo$lambda_optimo, 2)),
          showcase = icon("gears"),
          theme    = "primary",
          p(paste0("Calibrado por criterio ", metricas_modelo$criterio))
        ),
        value_box(
          title    = "Predictores Seleccionados",
          value    = paste0(metricas_modelo$n_activos, " de ", metricas_modelo$n_predictores),
          showcase = icon("filter"),
          theme    = "info",
          p("Series de sentimiento con β ≠ 0")
        ),
        value_box(
          title    = "Error Cuadrático Medio (RMSE)",
          value    = paste0(metricas_modelo$rmse, " pts"),
          showcase = icon("ruler-combined"),
          theme    = "secondary",
          p(paste0("Sobre ", metricas_modelo$n_observaciones, " meses efectivos"))
        )
      ),

      card(
        full_screen = TRUE,
        card_header(
          "Descomposición Aditiva de Atribuciones en el Tiempo (plot.attributions)"
        ),
        plotlyOutput("plot_atribuciones", height = "420px")
      ),

      layout_columns(
        col_widths = c(7, 5),
        card(
          full_screen = TRUE,
          card_header(
            "Desempeño del Modelo: Intensidad Delictiva Observada (y_t) vs. Predicha (ŷ_t)"
          ),
          plotlyOutput("plot_ajuste_elasticnet", height = "350px")
        ),
        card(
          full_screen = TRUE,
          card_header(
            "Top 15 Series de Sentimiento con Mayor Magnitud en Elastic Net (|β|)"
          ),
          plotlyOutput("plot_top_coeficientes", height = "350px")
        )
      )
    )
  ),

  # ============================================================================
  # PESTAÑA 4: NOTICIAS CRÍTICAS Y CORPUS (T-08, T-11, T-12)
  # ============================================================================
  nav_panel(
    title = "4. Noticias Críticas y Corpus",
    icon  = icon("newspaper"),
    navset_card_underline(
      title = "Exploración Documental y Estadísticas del Corpus",

      # Sub-pestaña 4.1: Explorador de peakdocs (T-12)
      nav_panel(
        title = "Noticias Críticas (peakdocs — T-12)",
        icon  = icon("magnifying-glass"),
        layout_sidebar(
          sidebar = sidebar(
            title = "Filtros de Noticias",
            width = 290,
            selectInput(
              "filtro_tipo_pico",
              "Subconjunto documental:",
              choices = c(
                "Documentos Pico y Extremos (peakdocs)" = "picos",
                "Solo Picos Negativos (Mayor Alarma)"   = "negativos",
                "Solo Picos Positivos (Operatividad)"   = "positivos",
                "Corpus Completo (3.916 noticias)"      = "todas"
              ),
              selected = "picos"
            ),
            selectInput(
              "filtro_loc_noticias",
              "Localidad:",
              choices  = c("Todas las localidades" = "todas", lista_localidades),
              selected = "todas"
            ),
            selectInput(
              "filtro_dai_noticias",
              "Categoría Oficial DAI (SDSCJ):",
              choices = c(
                "Todas las categorías" = "todas",
                sort(unique(tabla_noticias$delito_sdscj))
              ),
              selected = "todas"
            ),
            sliderInput(
              "filtro_anio_noticias",
              "Rango de años:",
              min   = 2022,
              max   = 2026,
              value = c(2022, 2026),
              sep   = ""
            )
          ),
          DTOutput("tabla_explorador_noticias")
        )
      ),

      # Sub-pestaña 4.2: Estadísticas descriptivas del corpus (T-08)
      nav_panel(
        title = "Evolución del Corpus y Léxicos (corpus_summarize — T-08)",
        icon  = icon("chart-column"),
        layout_columns(
          col_widths = c(6, 6),
          card(
            full_screen = TRUE,
            card_header("Evolución Mensual de Documentos y Extensión Léxica (corpus_summarize)"),
            plotlyOutput("plot_corpus_summarize_mes", height = "370px")
          ),
          card(
            full_screen = TRUE,
            card_header("Composición del Corpus según los 11 Delitos de Alto Impacto (SDSCJ)"),
            plotlyOutput("plot_composicion_dai", height = "370px")
          )
        ),
        layout_columns(
          col_widths = c(6, 6),
          card(
            full_screen = TRUE,
            card_header("Términos con Mayor Carga en el Léxico de Criminalidad (crimen_es)"),
            plotlyOutput("plot_lexico_crimen", height = "350px")
          ),
          card(
            full_screen = TRUE,
            card_header("Resumen Anual del Corpus Periodístico (2022–2026)"),
            DTOutput("tabla_resumen_anual_corpus")
          )
        )
      )
    )
  ),

  # ============================================================================
  # PESTAÑA 5: FICHA METODOLÓGICA Y ARQUITECTURA (T-01 a T-04, T-20)
  # ============================================================================
  nav_panel(
    title = "5. Metodología y Contratos",
    icon  = icon("book-open"),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("1. Formulación Matemática de Sentometrics (Ardia et al., 2021)"),
        div(
          class = "metodologia-box",
          h5("Ponderación en Tres Niveles (ω, θ, b) y Modificadores de Valencia"),
          p(
            "Para cada documento ", HTML("<i>i</i>"), " en el mes ", HTML("<i>t</i>"),
            ", el puntaje léxico incorpora una ventana contextual de modificadores de valencia ",
            HTML("(negadores <i>t=1</i>, amplificadores <i>t=2</i>, atenuadores <i>t=3</i> y adversativos <i>t=4</i>)"),
            " y se normaliza por el número de palabras polarizadas (",
            code("howWithin = 'proportionalPol'"), "):"
          ),
          p(
            "$$s_{i,t}^{(\\ell, k)} = f_{i,k} \\cdot \\frac{\\sum_{w \\in d_i} v_{w} \\cdot m_{w}^{(\\ell)}}{N_{\\text{pol}}(d_i)}$$"
          ),
          p(
            "Las noticias dentro del mes ", HTML("<i>t</i>"),
            " se agregan proporcionalmente a su longitud documental (",
            code("howDocs = 'proportional'"), " con ", code("do.ignoreZeros = TRUE"),
            ") y se suavizan en una ventana retrospectiva de ", HTML("<i>L = 6</i>"),
            " meses mediante pesos temporales ", HTML("<i>b_k</i>"),
            " (lineales, exponenciales y curvas Beta):"
          ),
          p(
            "$$S_{t}^{(\\ell, k, \\tau)} = \\sum_{j=0}^{L-1} b_j^{(\\tau)} \\left( \\sum_{i=1}^{D_{t-j}} \\theta_{i, t-j} \\, s_{i, t-j}^{(\\ell, k)} \\right)$$"
          )
        ),
        div(
          class = "metodologia-box",
          h5("Regresión Penalizada Elastic Net y Descomposición de Atribuciones"),
          p(
            "Dada la alta dimensionalidad del panel de sentimiento (",
            HTML("<i>M = 364</i>"), " series mensuales producto de ",
            "26 features × 2 léxicos × 7 esquemas temporales), estimamos con ",
            code("sento_model()"), " una regresión con penalización mixta L1/L2:"
          ),
          p(
            "$$\\min_{\\beta_0, \\beta} \\left\\{ \\frac{1}{2N} \\sum_{t=1}^{N} \\left(y_{t+h} - \\beta_0 - \\sum_{m=1}^{M} \\beta_m S_{t,m}\\right)^2 + \\lambda \\left[ \\frac{1-\\alpha}{2} \\|\\beta\\|_2^2 + \\alpha \\|\\beta\\|_1 \\right] \\right\\}$$"
          ),
          p(
            "Aprovechando la linealidad del predictor, ", code("attributions()"),
            " descompone de manera exacta el aporte marginal de cada localidad, clúster, léxico y horizonte temporal en cada fecha."
          )
        )
      ),
      card(
        card_header("2. Contrato de Objetos S3 (.rds) y Tareas del Equipo (T-01 a T-20)"),
        p(
          "Todos los artefactos procesados se encuentran validados en ",
          code("data/processed/"), " y pre-empaquetados en ",
          code("datos_consolidados_shiny.rds"), ":"
        ),
        DTOutput("tabla_contrato_rds")
      )
    )
  )
)

# 4. Lógica del Servidor (Server) ----

server <- function(input, output, session) {

  # ----------------------------------------------------------------------------
  # 4.1 Reactivos de la Pestaña 1: Panorama Territorial y Clústeres
  # ----------------------------------------------------------------------------
  datos_terr_filtrados <- reactive({
    req(input$filtro_cluster_terr)
    df <- panel_localidades |>
      filter(cluster_nombre %in% input$filtro_cluster_terr)

    if (input$anio_terr == "todos") {
      df_res <- df |>
        group_by(
          codigo_localidad, localidad, cluster_id,
          cluster_nombre, perfil_seguridad
        ) |>
        summarise(
          poblacion              = round(mean(poblacion, na.rm = TRUE)),
          hurto_personas         = sum(hurto_personas, na.rm = TRUE),
          hurto_residencias      = sum(hurto_residencias, na.rm = TRUE),
          hurto_motos            = sum(hurto_motos, na.rm = TRUE),
          tasa_hurto_personas    = round(mean(tasa_hurto_personas, na.rm = TRUE), 1),
          tasa_hurto_residencias = round(mean(tasa_hurto_residencias, na.rm = TRUE), 1),
          tasa_hurto_motos       = round(mean(tasa_hurto_motos, na.rm = TRUE), 1),
          tasa_hurto_total       = round(mean(tasa_hurto_total, na.rm = TRUE), 1),
          noticias_conteo        = sum(noticias_conteo, na.rm = TRUE),
          noticias_dai_conteo    = sum(noticias_dai_conteo, na.rm = TRUE),
          sentimiento_promedio   = round(mean(sentimiento_promedio, na.rm = TRUE), 4),
          prop_negativas         = round(mean(prop_negativas, na.rm = TRUE), 1),
          .groups = "drop"
        )
    } else {
      df_res <- df |>
        filter(año == as.integer(input$anio_terr))
    }

    df_res |>
      mutate(tasa_activa = .data[[input$metrica_hurto]])
  })

  output$kpi_tasa_media <- renderText({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)
    scales::comma(round(mean(df$tasa_activa, na.rm = TRUE), 1))
  })

  output$kpi_loc_critica <- renderText({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)
    top_row <- df |> slice_max(tasa_activa, n = 1, with_ties = FALSE)
    top_row$localidad
  })

  output$kpi_loc_critica_sub <- renderText({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)
    top_row <- df |> slice_max(tasa_activa, n = 1, with_ties = FALSE)
    paste0(
      scales::comma(round(top_row$tasa_activa, 1)),
      " por 100k hab. (",
      top_row$cluster_nombre,
      ")"
    )
  })

  output$kpi_sent_medio <- renderText({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)
    sprintf("%+.4f", mean(df$sentimiento_promedio, na.rm = TRUE))
  })

  output$kpi_prop_neg <- renderText({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)
    paste0(round(mean(df$prop_negativas, na.rm = TRUE), 1), "%")
  })

  output$kpi_total_noticias_sub <- renderText({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)
    paste0(
      scales::comma(sum(df$noticias_conteo, na.rm = TRUE)),
      " noticias (",
      scales::comma(sum(df$noticias_dai_conteo, na.rm = TRUE)),
      " DAI)"
    )
  })

  output$mapa_bogota <- renderLeaflet({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0, !is.null(geo_localidades))

    capa_sf <- geo_localidades |>
      select(codigo_localidad, geometry) |>
      inner_join(df, by = "codigo_localidad")

    if (input$capa_mapa == "cluster") {
      pal <- colorFactor(
        palette = unname(colores_cluster),
        domain  = names(colores_cluster)
      )
      valores_fill <- capa_sf$cluster_nombre
      titulo_leyenda <- "Clúster K-Means"
    } else if (input$capa_mapa == "tasa") {
      pal <- colorNumeric(
        palette = "YlOrRd",
        domain  = capa_sf$tasa_activa
      )
      valores_fill <- capa_sf$tasa_activa
      titulo_leyenda <- "Tasa por 100k hab."
    } else {
      pal <- colorNumeric(
        palette = "RdYlGn",
        domain  = capa_sf$sentimiento_promedio
      )
      valores_fill <- capa_sf$sentimiento_promedio
      titulo_leyenda <- "Sentimiento Neto"
    }

    popups_html <- sprintf(
      "<strong>%s (Cód. %s)</strong><br/>
       <span style='color:#1b365d;font-weight:600;'>%s</span><br/><hr style='margin:4px 0;'/>
       <b>Tasa Hurto Total:</b> %s por 100k hab.<br/>
       <b>• Hurto Personas:</b> %s<br/>
       <b>• Hurto Residencias:</b> %s<br/>
       <b>• Hurto Motos:</b> %s<br/><hr style='margin:4px 0;'/>
       <b>Noticias analizadas:</b> %s (%s DAI)<br/>
       <b>Sentimiento promedio:</b> %+.4f (%s%% negativas)",
      capa_sf$localidad,
      capa_sf$codigo_localidad,
      capa_sf$cluster_nombre,
      scales::comma(capa_sf$tasa_hurto_total),
      scales::comma(capa_sf$tasa_hurto_personas),
      scales::comma(capa_sf$tasa_hurto_residencias),
      scales::comma(capa_sf$tasa_hurto_motos),
      scales::comma(capa_sf$noticias_conteo),
      scales::comma(capa_sf$noticias_dai_conteo),
      capa_sf$sentimiento_promedio,
      capa_sf$prop_negativas
    )

    leaflet(capa_sf) |>
      addProviderTiles(providers$CartoDB.Positron) |>
      addPolygons(
        fillColor   = ~pal(valores_fill),
        weight      = 1.5,
        opacity     = 1,
        color       = "#ffffff",
        dashArray   = "1",
        fillOpacity = 0.78,
        highlightOptions = highlightOptions(
          weight       = 3,
          color        = "#1b365d",
          fillOpacity  = 0.92,
          bringToFront = TRUE
        ),
        label = ~paste0(localidad, " — ", cluster_nombre),
        popup = popups_html
      ) |>
      addLegend(
        pal      = pal,
        values   = valores_fill,
        opacity  = 0.85,
        title    = titulo_leyenda,
        position = "bottomright"
      )
  })

  output$plot_cruce_hurto_sent <- renderPlotly({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)

    etiqueta_y <- names(catalogo_tasas)[catalogo_tasas == input$metrica_hurto]

    p <- ggplot(
      df,
      aes(
        x     = tasa_activa,
        y     = sentimiento_promedio,
        color = cluster_nombre,
        size  = noticias_conteo,
        text  = paste0(
          "<b>", localidad, "</b><br>",
          "Clúster: ", cluster_nombre, "<br>",
          etiqueta_y, ": ", scales::comma(tasa_activa), "<br>",
          "Sentimiento neto: ", sprintf("%+.4f", sentimiento_promedio), "<br>",
          "Noticias negativas: ", prop_negativas, "%<br>",
          "Volumen noticias: ", noticias_conteo
        )
      )
    ) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "gray60") +
      geom_point(alpha = 0.85) +
      scale_color_manual(values = colores_cluster) +
      scale_x_continuous(labels = scales::comma) +
      labs(
        x     = etiqueta_y,
        y     = "Sentimiento Mediático Promedio (sentometrics)",
        color = "Clúster Territorial",
        size  = "N° Noticias"
      ) +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text") |>
      layout(legend = list(orientation = "h", y = -0.2))
  })

  output$plot_ranking_localidades <- renderPlotly({
    df <- datos_terr_filtrados()
    req(nrow(df) > 0)

    etiqueta_x <- names(catalogo_tasas)[catalogo_tasas == input$metrica_hurto]

    p <- ggplot(
      df,
      aes(
        x    = reorder(localidad, tasa_activa),
        y    = tasa_activa,
        fill = cluster_nombre,
        text = paste0(
          "<b>", localidad, "</b><br>",
          etiqueta_x, ": ", scales::comma(tasa_activa), "<br>",
          "Clúster: ", cluster_nombre
        )
      )
    ) +
      geom_col(width = 0.72) +
      coord_flip() +
      scale_fill_manual(values = colores_cluster) +
      scale_y_continuous(labels = scales::comma) +
      labs(
        x    = NULL,
        y    = etiqueta_x,
        fill = "Clúster Territorial"
      ) +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text") |>
      layout(showlegend = FALSE)
  })

  output$tabla_perfiles_kmeans <- renderDT({
    resumen <- clusters_perfiles |>
      group_by(cluster_id, cluster_nombre, perfil_seguridad) |>
      summarise(
        n_localidades     = n(),
        hurto_personas    = round(mean(tasa_personas_prom), 1),
        hurto_residencias = round(mean(tasa_resid_prom), 1),
        hurto_motos       = round(mean(tasa_motos_prom), 1),
        tasa_total        = round(mean(tasa_total_prom), 1),
        silueta_media     = round(mean(silueta_localidad), 3),
        localidades       = paste(localidad, collapse = ", "),
        .groups = "drop"
      ) |>
      arrange(cluster_id)

    datatable(
      resumen |> select(-cluster_id),
      rownames = FALSE,
      colnames = c(
        "Clúster", "Caracterización", "N° Locs",
        "Tasa Personas", "Tasa Resid.", "Tasa Motos",
        "Tasa Total", "Silueta", "Localidades Miembro"
      ),
      options = list(dom = "t", pageLength = 5, scrollX = TRUE)
    )
  })

  # ----------------------------------------------------------------------------
  # 4.2 Reactivos de la Pestaña 2: Series de Sentimiento (T-16)
  # ----------------------------------------------------------------------------
  output$ui_selector_features_serie <- renderUI({
    req(input$grupo_serie)
    df_sub <- measures_long |>
      filter(grupo_feature == input$grupo_serie) |>
      distinct(feature, feature_label) |>
      arrange(feature_label)

    opciones <- setNames(df_sub$feature, df_sub$feature_label)
    seleccion_inicial <- if (input$grupo_serie == "Localidad") {
      head(opciones, 5)
    } else {
      opciones
    }

    selectizeInput(
      "features_serie_sel",
      "2. Seleccionar series a comparar:",
      choices  = opciones,
      selected = seleccion_inicial,
      multiple = TRUE,
      options  = list(plugins = list("remove_button"))
    )
  })

  output$plot_series_measures <- renderPlotly({
    req(input$features_serie_sel, input$lexico_serie, input$tiempo_serie)

    df_plot <- measures_long |>
      filter(
        feature %in% input$features_serie_sel,
        lexicon == input$lexico_serie,
        time    == input$tiempo_serie
      )

    req(nrow(df_plot) > 0)

    p <- ggplot(
      df_plot,
      aes(
        x     = date,
        y     = valor,
        color = feature_label,
        group = feature_label,
        text  = paste0(
          "<b>", feature_label, "</b><br>",
          "Fecha: ", format(date, "%Y-%m"), "<br>",
          "Sentimiento agregado: ", sprintf("%+.4f", valor), "<br>",
          "Léxico: ", lexicon_label, "<br>",
          "Esquema temporal: ", time
        )
      )
    ) +
      geom_hline(yintercept = 0, linetype = "dotted", color = "gray45") +
      geom_line(linewidth = 0.9)

    if (isTRUE(input$mostrar_peakdates)) {
      p <- p +
        geom_vline(
          xintercept = as.numeric(peakdates_neg),
          linetype   = "dashed",
          color      = "#c0392b",
          alpha      = 0.35
        )
    }

    p <- p +
      scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
      labs(
        x     = "Mes de agregación (ventana móvil de 6 meses)",
        y     = "Índice de Sentimiento Ponderado",
        color = "Serie (Feature)"
      ) +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text") |>
      layout(legend = list(orientation = "h", y = -0.22))
  })

  output$plot_indice_global <- renderPlotly({
    df_g <- global_index_df |>
      select(date, `Índice Global Total` = global, `Dimensión Léxica` = globLex, `Dimensión Temporal` = globTime) |>
      pivot_longer(cols = -date, names_to = "componente", values_to = "valor")

    p <- ggplot(
      df_g,
      aes(
        x     = date,
        y     = valor,
        color = componente,
        group = componente,
        text  = paste0(
          "<b>", componente, "</b><br>",
          "Fecha: ", format(date, "%Y-%m"), "<br>",
          "Valor: ", sprintf("%+.4f", valor)
        )
      )
    ) +
      geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
      geom_line(linewidth = 0.85) +
      scale_color_manual(
        values = c(
          "Índice Global Total" = "#1b365d",
          "Dimensión Léxica"    = "#c0392b",
          "Dimensión Temporal"  = "#2980b9"
        )
      ) +
      labs(x = "Fecha", y = "Índice Global", color = NULL) +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text") |>
      layout(legend = list(orientation = "h", y = -0.22))
  })

  output$tabla_peakdates <- renderDT({
    df_picos <- global_index_df |>
      filter(tipo_pico != "Normal") |>
      transmute(
        Fecha        = format(date, "%Y-%m"),
        Tipo_Pico    = tipo_pico,
        Indice_Global = round(global, 4),
        Indice_Lexico = round(globLex, 4)
      ) |>
      arrange(Indice_Global)

    datatable(
      df_picos,
      rownames = FALSE,
      colnames = c("Mes Crítico", "Clasificación peakdates()", "Índice Global", "Componente Léxico"),
      options  = list(pageLength = 6, dom = "tp")
    )
  })

  # ----------------------------------------------------------------------------
  # 4.3 Reactivos de la Pestaña 3: Impacto y Atribuciones (T-18)
  # ----------------------------------------------------------------------------
  output$plot_atribuciones <- renderPlotly({
    req(input$dim_atribucion, input$escala_atribucion)

    df_base <- if (input$escala_atribucion == "norm") attr_long_norm else attr_long_raw
    df_dim  <- df_base |> filter(dimension == input$dim_atribucion)

    if (input$dim_atribucion == "features") {
      req(input$subgrupo_attr_feat)
      if (input$subgrupo_attr_feat == "clusters") {
        df_dim <- df_dim |> filter(str_starts(componente, "c_"))
      } else if (input$subgrupo_attr_feat == "temas") {
        df_dim <- df_dim |> filter(str_starts(componente, "tema_"))
      } else {
        top_locs <- df_dim |>
          filter(str_starts(componente, "loc_")) |>
          group_by(componente) |>
          summarise(mag = sum(abs(atribucion), na.rm = TRUE), .groups = "drop") |>
          slice_max(mag, n = 8) |>
          pull(componente)
        df_dim <- df_dim |> filter(componente %in% top_locs)
      }
    }

    p <- ggplot(
      df_dim,
      aes(
        x    = date,
        y    = atribucion,
        fill = componente_label,
        text = paste0(
          "<b>", componente_label, "</b><br>",
          "Mes: ", format(date, "%Y-%m"), "<br>",
          "Atribución: ", sprintf("%+.4f", atribucion)
        )
      )
    ) +
      geom_col(position = "stack", width = 22) +
      geom_hline(yintercept = 0, color = "black", linewidth = 0.3) +
      scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
      labs(
        x    = "Fecha de pronóstico",
        y    = if (input$escala_atribucion == "norm") "Atribución Normalizada [-1, 1]" else "Aporte Marginal a la Tasa de Hurto",
        fill = "Componente"
      ) +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text") |>
      layout(legend = list(orientation = "h", y = -0.25))
  })

  output$plot_ajuste_elasticnet <- renderPlotly({
    df_aj <- ajuste_temporal |>
      select(date, `Observada (y_t)` = observado, `Predicha Elastic Net (ŷ_t)` = predicho) |>
      pivot_longer(cols = -date, names_to = "serie", values_to = "valor")

    p <- ggplot(
      df_aj,
      aes(
        x     = date,
        y     = valor,
        color = serie,
        linetype = serie,
        group = serie,
        text  = paste0(
          "<b>", serie, "</b><br>",
          "Mes: ", format(date, "%Y-%m"), "<br>",
          "Tasa mensualizada: ", scales::comma(valor)
        )
      )
    ) +
      geom_line(linewidth = 0.95) +
      scale_color_manual(
        values = c(
          "Observada (y_t)"            = "#1b365d",
          "Predicha Elastic Net (ŷ_t)" = "#c0392b"
        )
      ) +
      labs(
        x     = "Fecha (h = 1 mes adelante)",
        y     = "Tasa mensualizada por 100k hab.",
        color = NULL,
        linetype = NULL
      ) +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text") |>
      layout(legend = list(orientation = "h", y = -0.22))
  })

  output$plot_top_coeficientes <- renderPlotly({
    df_top <- coeficientes_df |>
      slice_head(n = 15) |>
      mutate(
        signo = ifelse(coeficiente >= 0, "Positivo (+)", "Negativo (-)")
      )

    p <- ggplot(
      df_top,
      aes(
        x    = reorder(variable, abs(coeficiente)),
        y    = coeficiente,
        fill = signo,
        text = paste0(
          "<b>", variable, "</b><br>",
          "Coeficiente β: ", round(coeficiente, 4)
        )
      )
    ) +
      geom_col(width = 0.7) +
      coord_flip() +
      scale_fill_manual(
        values = c("Positivo (+)" = "#2980b9", "Negativo (-)" = "#c0392b")
      ) +
      labs(x = NULL, y = "Magnitud del Coeficiente (β)", fill = "Signo") +
      theme_minimal(base_size = 10)

    ggplotly(p, tooltip = "text") |>
      layout(showlegend = FALSE)
  })

  # ----------------------------------------------------------------------------
  # 4.4 Reactivos de la Pestaña 4: Noticias Críticas y Corpus (T-08, T-12)
  # ----------------------------------------------------------------------------
  noticias_filtradas_dt <- reactive({
    df <- tabla_noticias |>
      filter(
        año >= input$filtro_anio_noticias[1],
        año <= input$filtro_anio_noticias[2]
      )

    if (input$filtro_tipo_pico == "picos") {
      df <- df |> filter(tipo_pico != "Regular")
    } else if (input$filtro_tipo_pico == "negativos") {
      df <- df |> filter(sentimiento_score < 0) |> arrange(sentimiento_score) |> slice_head(n = 150)
    } else if (input$filtro_tipo_pico == "positivos") {
      df <- df |> filter(sentimiento_score > 0) |> arrange(desc(sentimiento_score)) |> slice_head(n = 150)
    }

    if (input$filtro_loc_noticias != "todas") {
      df <- df |> filter(localidad == input$filtro_loc_noticias)
    }

    if (input$filtro_dai_noticias != "todas") {
      df <- df |> filter(delito_sdscj == input$filtro_dai_noticias)
    }

    df
  })

  output$tabla_explorador_noticias <- renderDT({
    df <- noticias_filtradas_dt() |>
      transmute(
        Fecha       = as.character(fecha),
        Localidad   = localidad,
        Cluster     = cluster_nombre,
        Delito_DAI  = delito_sdscj,
        Titular     = paste0("<b>", titulo, "</b><br/><small class='text-muted'>", fuente, "</small>"),
        Score_Neto  = sentimiento_score,
        Polaridad   = case_when(
          sentimiento_categoria == "Negativo" ~ "<span class='badge-negativo'>Negativo</span>",
          sentimiento_categoria == "Positivo" ~ "<span class='badge-positivo'>Positivo</span>",
          TRUE                                ~ "<span class='badge-neutro'>Neutro</span>"
        ),
        Clasif_Pico = tipo_pico,
        Enlace      = ifelse(
          !is.na(enlace) & enlace != "",
          paste0("<a href='", enlace, "' target='_blank' class='btn btn-sm btn-outline-primary'>Abrir nota</a>"),
          "—"
        )
      )

    datatable(
      df,
      escape   = FALSE,
      rownames = FALSE,
      colnames = c(
        "Fecha", "Localidad", "Clúster", "Modalidad SDSCJ",
        "Titular y Medio", "Score Sentometrics", "Polaridad",
        "Categoría peakdocs", "Fuente"
      ),
      options = list(
        pageLength = 10,
        scrollX    = TRUE,
        language   = list(
          search = "Buscar titular o palabra clave:",
          info   = "Mostrando _START_ a _END_ de _TOTAL_ noticias"
        )
      )
    )
  })

  output$plot_corpus_summarize_mes <- renderPlotly({
    p <- ggplot(
      corpus_stats_mes,
      aes(
        x    = as.Date(date),
        y    = documents,
        text = paste0(
          "<b>Mes: ", format(as.Date(date), "%Y-%m"), "</b><br>",
          "Documentos: ", documents, "<br>",
          "Tokens promedio: ", round(meanTokens, 1)
        )
      )
    ) +
      geom_col(fill = "#1b365d", alpha = 0.85) +
      scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
      labs(
        x = "Mes de publicación",
        y = "Número de noticias (corpus_summarize)"
      ) +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text")
  })

  output$plot_composicion_dai <- renderPlotly({
    df_dai <- tabla_noticias |>
      count(delito_sdscj, name = "articulos") |>
      arrange(articulos)

    p <- ggplot(
      df_dai,
      aes(
        x    = reorder(delito_sdscj, articulos),
        y    = articulos,
        fill = delito_sdscj == "No DAI",
        text = paste0(
          "<b>", delito_sdscj, "</b><br>",
          "Artículos: ", scales::comma(articulos)
        )
      )
    ) +
      geom_col(width = 0.72) +
      coord_flip() +
      scale_fill_manual(values = c("FALSE" = "#2980b9", "TRUE" = "#95a5a6")) +
      labs(x = NULL, y = "Número de noticias clasificadas") +
      theme_minimal(base_size = 11)

    ggplotly(p, tooltip = "text") |>
      layout(showlegend = FALSE)
  })

  output$plot_lexico_crimen <- renderPlotly({
    df_lex <- lexicos_info$crimen_es |>
      mutate(polaridad = ifelse(y > 0, "Respuesta Institucional (+)", "Delito / Violencia (-)")) |>
      group_by(polaridad) |>
      slice_max(abs(y), n = 12, with_ties = FALSE) |>
      ungroup()

    p <- ggplot(
      df_lex,
      aes(
        x    = reorder(x, y),
        y    = y,
        fill = polaridad,
        text = paste0("Término: <b>", x, "</b><br>Valencia y: ", y)
      )
    ) +
      geom_col(width = 0.7) +
      coord_flip() +
      scale_fill_manual(
        values = c("Respuesta Institucional (+)" = "#27ae60", "Delito / Violencia (-)" = "#c0392b")
      ) +
      labs(x = NULL, y = "Puntuación de valencia (y)", fill = NULL) +
      theme_minimal(base_size = 10)

    ggplotly(p, tooltip = "text")
  })

  output$tabla_resumen_anual_corpus <- renderDT({
    df_anual <- tabla_noticias |>
      group_by(año) |>
      summarise(
        Total_Noticias = n(),
        Noticias_DAI   = sum(es_dai_estricto, na.rm = TRUE),
        Media_Palabras = round(mean(word_count, na.rm = TRUE), 1),
        Score_NRC      = round(mean(score_nrc_es, na.rm = TRUE), 4),
        Score_Crimen   = round(mean(score_crimen_es, na.rm = TRUE), 4),
        Score_Neto     = round(mean(sentimiento_score, na.rm = TRUE), 4),
        .groups = "drop"
      )

    datatable(
      df_anual,
      rownames = FALSE,
      colnames = c(
        "Año", "Noticias Totales", "Noticias 11 DAI",
        "Tokens Prom.", "Media NRC", "Media Crimen", "Score Combinado"
      ),
      options = list(dom = "t", pageLength = 6)
    )
  })

  # ----------------------------------------------------------------------------
  # 4.5 Reactivos de la Pestaña 5: Contrato de Objetos .rds
  # ----------------------------------------------------------------------------
  output$tabla_contrato_rds <- renderDT({
    contrato_df <- tibble::tribble(
      ~Tarea, ~Fase, ~Archivo, ~Clase_S3, ~Descripcion,
      "T-07", "Fase 1: Corpus", "data/processed/01_sento_corpus.rds", "sento_corpus", "Corpus de 3.916 noticias con 26 features binarias (19 localidades + 3 clústeres + 4 tópicos DAI) sin guiones '-'.",
      "T-08", "Fase 1: Corpus", "output/figures/figura8-9_*.png", "corpus_summarize", "Estadísticos mensuales y anuales de documentos, tokens y cobertura por característica.",
      "T-09", "Fase 2: Léxicos", "data/processed/02_lexicons_es.rds", "sento_lexicons", "Diccionarios nrc_es y crimen_es + tabla de modificadores de valencia valenceIn (t = 1..4).",
      "T-10", "Fase 2: Sentimiento", "data/processed/03_sentiment_scores.rds", "sentiment", "Puntuaciones a nivel documento con how = 'proportionalPol' y validación cruzada frente a TFIDF.",
      "T-11", "Fase 2: Picos", "data/processed/04_peak_docs.rds", "list / data.table", "Extracción de noticias más extremas con peakdocs() enriquecida con metadatos para Shiny.",
      "T-13", "Fase 3: Measures", "data/processed/05_sento_measures.rds", "sento_measures", "364 series mensuales con ctr_agg(proportionalPol, proportional, linear/exponential/beta, lag = 6).",
      "T-14", "Fase 3: Series Long", "data/processed/06_measures_long.rds", "list (long/wide)", "Continuidad auditada con measures_fill() y tabla long de 18.928 observaciones para Plotly.",
      "T-15", "Fase 3: Índice Global", "data/processed/07_global_index.rds", "list / data.table", "Índice agregado distrital (aggregate do.global = TRUE) y detección de meses críticos con peakdates().",
      "T-17", "Fase 4: Atribuciones", "data/processed/08_attributions.rds", "sento_model / attributions", "Modelo Elastic Net (BIC, h = 1) sobre tasa mensual empírica real y descomposición por features, lexicons y time."
    )

    datatable(
      contrato_df,
      rownames = FALSE,
      colnames = c("ID Tarea", "Fase", "Ruta del Entregable", "Clase S3", "Contenido Técnico"),
      options  = list(dom = "t", pageLength = 10, scrollX = TRUE)
    )
  })
}

# 5. Ejecución de la Aplicación ----
shinyApp(ui = ui, server = server)
