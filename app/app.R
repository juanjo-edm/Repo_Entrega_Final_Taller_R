# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: app/app.R
# ROL: App Shiny "Dos lecturas de Bogotá" (versión en R del boceto de diseño)
# AUTORA: Olga Lucía Ramírez (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# LEE: data/processed/datos_consolidados_shiny.rds (generado por scripts/master.R)
# CÓMO CORRERLA: shiny::runApp(here::here("app"))
# ==============================================================================
#
# Idea de diseño: la app compara dos "lecturas" de la inseguridad.
#   - Ámbar (#F0A43A): lo que dicen las denuncias (tasas de hurto oficiales).
#   - Azul  (#79AEFF): lo que dice la prensa (sentimiento de las noticias).
#
# Pestañas:
#   1. Panorama          -> cifras clave, mapa y ranking
#   2. Mi localidad      -> ficha de una localidad
#   3. Hurto vs. prensa  -> gráfico de dispersión (la pregunta del proyecto)
#   4. Clusters          -> los 3 grupos de K-means
#   5. Datos y método    -> fuentes y advertencias

# 1. Configuración y Dependencias ----

## 1.1 Librerías ----
library(shiny)
library(bslib)
library(here)
library(conflicted)
library(dplyr)
library(tidyr)
library(plotly)
library(DT)
library(leaflet)
library(sf)

## 1.2 Resolución de conflictos ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("layout", "plotly", quiet = TRUE)

# 2. Carga de Datos ----

## 2.1 Lectura del bundle consolidado ----
ruta_bundle <- here::here("data", "processed", "datos_consolidados_shiny.rds")
if (!file.exists(ruta_bundle)) {
  stop("No se encontró datos_consolidados_shiny.rds. Corra primero scripts/master.R")
}

datos_app <- readRDS(ruta_bundle)

panel_localidades <- as_tibble(datos_app$panel_localidades)          # localidad x año
clusters_perfiles <- as_tibble(datos_app$clusters_perfiles)          # perfiles K-means
geo_localidades   <- datos_app$geometrias                            # polígonos (sf)
corpus_stats_mes  <- as_tibble(datos_app$corpus_stats_mes)           # corpus_summarize mes
corpus_stats_anio <- as_tibble(datos_app$corpus_stats_anio)          # corpus_summarize año
lexicos_info      <- datos_app$lexicos_info                          # léxicos y modificadores
tabla_noticias    <- as_tibble(datos_app$peak_docs$tabla_completa)   # una fila por noticia
measures_long     <- as_tibble(datos_app$measures_long)              # series sento_measures
global_index_df   <- as_tibble(datos_app$global_index$serie_global)  # índice global
peakdates_neg     <- datos_app$global_index$peakdates_neg            # picos negativos
peakdates_pos     <- datos_app$global_index$peakdates_pos            # picos positivos
attr_long_raw     <- as_tibble(datos_app$attributions$attr_long_raw) # atribuciones crudas
attr_long_norm    <- as_tibble(datos_app$attributions$attr_long_norm)# atribuciones norm.
ajuste_temporal   <- as_tibble(datos_app$attributions$ajuste_temporal)
coeficientes_df   <- as_tibble(datos_app$attributions$coeficientes)
metricas_modelo   <- datos_app$attributions$metricas_modelo

## 2.2 Listas y colores que usa toda la app ----
lista_localidades <- sort(unique(panel_localidades$localidad))

modalidades <- c(
  "Personas"     = "tasa_hurto_personas",
  "Residencias"  = "tasa_hurto_residencias",
  "Motocicletas" = "tasa_hurto_motos"
)

medidas_prensa <- c(
  "% de noticias negativas"   = "prop_negativas",
  "Sentimiento neto promedio" = "sentimiento_promedio",
  "Número de noticias"        = "noticias_conteo"
)

opciones_anio <- c(
  "Promedio 2022–2026" = "todos",
  "2022" = "2022", "2023" = "2023", "2024" = "2024", "2025" = "2025",
  "2026 (ene–sep)" = "2026"
)

colores_cluster <- c(
  "Céntrico e Institucional" = "#B08CF0",
  "Comercial y Automotor"    = "#E86A50",
  "Residencial y Periférico" = "#3FB8A6"
)

ambar      <- "#F0A43A"
azul       <- "#79AEFF"
gris_texto <- "#9AA4B2"
fondo      <- "#0E1116"
tarjeta    <- "#171B22"
borde      <- "#2A303A"

# 3. Funciones de Apoyo ----

## 3.1 Formato de números al estilo colombiano (1.234,5) ----
formato <- function(x, digitos = 0) {
  format(round(x, digitos), big.mark = ".", decimal.mark = ",",
         nsmall = digitos, trim = TRUE)
}

## 3.2 Resumen del panel para un año o para el promedio 2022-2026 ----
resumir_panel <- function(anio) {
  if (anio == "todos") {
    panel_localidades |>
      group_by(codigo_localidad, localidad, cluster_nombre) |>
      summarise(
        tasa_hurto_personas    = mean(tasa_hurto_personas, na.rm = TRUE),
        tasa_hurto_residencias = mean(tasa_hurto_residencias, na.rm = TRUE),
        tasa_hurto_motos       = mean(tasa_hurto_motos, na.rm = TRUE),
        noticias_conteo        = sum(noticias_conteo, na.rm = TRUE),
        sentimiento_promedio   = mean(sentimiento_promedio, na.rm = TRUE),
        prop_negativas         = mean(prop_negativas, na.rm = TRUE),
        .groups = "drop"
      )
  } else {
    panel_localidades |>
      filter(año == as.integer(anio))
  }
}

## 3.3 Paleta de 4 niveles (cuartiles) para los mapas ----
paleta_cuartiles <- function(valores, colores) {
  cortes <- unique(quantile(valores, probs = seq(0, 1, 0.25), na.rm = TRUE))
  colorBin(colores, domain = valores, bins = cortes)
}

## 3.4 Estilo oscuro común para todos los gráficos plotly ----
estilo_plotly <- function(p, titulo_x = "", titulo_y = "") {
  p |>
    layout(
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor  = "rgba(0,0,0,0)",
      font   = list(color = "#E9EDF2", family = "Archivo"),
      xaxis  = list(title = titulo_x, gridcolor = borde, zerolinecolor = borde),
      yaxis  = list(title = titulo_y, gridcolor = borde, zerolinecolor = borde),
      legend = list(orientation = "h", y = -0.2)
    ) |>
    config(displayModeBar = FALSE)
}

## 3.5 Tarjeta de cifra clave (value box) con estilo oscuro ----
tarjeta_cifra <- function(titulo, salida, nota, color) {
  value_box(
    title = titulo,
    value = span(textOutput(salida, inline = TRUE), style = paste0("color:", color)),
    p(nota, style = paste0("color:", gris_texto)),
    theme = value_box_theme(bg = tarjeta, fg = "#E9EDF2")
  )
}

## 3.6 Mapa base oscuro gratuito (OpenStreetMap + filtro oscuro CSS, sin API key) ----
agregar_mapa_base <- function(mapa) {
  mapa |>
    addTiles(
      urlTemplate = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
      attribution = "&copy; OpenStreetMap contributors"
    )
}

# 4. Tema Visual ----

tema_dos_lecturas <- bs_theme(
  version   = 5,
  bg        = fondo,
  fg        = "#E9EDF2",
  primary   = ambar,
  secondary = azul,
  base_font = font_google("Archivo"),
  code_font = font_google("IBM Plex Mono"),
  "card-bg"      = tarjeta,
  "border-color" = borde
)

# 5. Interfaz de Usuario (UI) ----

ui <- page_navbar(
  id       = "pestanas",
  title    = "Dos lecturas de Bogotá",
  theme    = tema_dos_lecturas,
  fillable = FALSE,
  header   = tags$head(
    tags$style(HTML("
      .leaflet-container {
        background-color: #0E1116 !important;
      }
      .leaflet-tile-pane {
        filter: invert(100%) hue-rotate(180deg) brightness(85%) contrast(90%) saturate(25%);
      }
    "))
  ),

  ## 5.1 Pestaña 1: Panorama ----
  nav_panel(
    title = "Panorama", value = "panorama",
    p("Hurtos denunciados y tono de la prensa · 19 localidades · 2022–2026",
      style = paste0("color:", gris_texto)),

    layout_columns(
      col_widths = c(4, 4, 4),
      radioButtons("modalidad", "Modalidad de hurto", choices = modalidades, inline = TRUE),
      selectInput("anio", "Año", choices = opciones_anio),
      radioButtons("capa_mapa", "Colorear el mapa por",
                   choices = c("Denuncias (hurto)" = "hurto", "Prensa" = "prensa"),
                   inline = TRUE)
    ),
    conditionalPanel(
      "input.capa_mapa == 'prensa'",
      selectInput("medida", "Medida de prensa", choices = medidas_prensa)
    ),

    layout_columns(
      col_widths = c(3, 3, 3, 3),
      tarjeta_cifra("Tasa promedio de hurto", "kpi_tasa",
                    "hurtos por 100.000 habitantes al año", ambar),
      tarjeta_cifra("Noticias analizadas", "kpi_noticias",
                    "Google News", azul),
      tarjeta_cifra("Sentimiento neto promedio", "kpi_sentimiento",
                    "sentometrics", azul),
      tarjeta_cifra("Noticias con tono negativo", "kpi_negativas",
                    "promedio de las localidades", azul)
    ),

    layout_columns(
      col_widths = c(8, 4),
      card(
        card_header("¿Dónde se concentra el hurto? · clic en una localidad para ver su ficha"),
        leafletOutput("mapa_panorama", height = "480px")
      ),
      card(
        card_header("Las 5 tasas más altas"),
        plotlyOutput("grafico_top5", height = "300px"),
        p("Ojo: la tasa usa población residente. El centro recibe cada día trabajadores
           y visitantes de toda la ciudad, así que su tasa se infla.",
          style = paste0("color:", gris_texto, "; font-size: 13px"))
      )
    )
  ),

  ## 5.2 Pestaña 2: Mi localidad ----
  nav_panel(
    title = "Mi localidad", value = "localidad",
    layout_columns(
      col_widths = c(4, 8),
      selectInput("localidad", "Localidad", choices = lista_localidades,
                  selected = "Chapinero"),
      p("También puedes llegar aquí haciendo clic en el mapa del Panorama.",
        style = paste0("color:", gris_texto, "; margin-top: 32px"))
    ),

    card(uiOutput("ficha_titulo")),

    layout_columns(
      col_widths = c(4, 4, 4),
      tarjeta_cifra("Hurto a personas", "loc_personas", "por 100.000 hab. (promedio)", ambar),
      tarjeta_cifra("Hurto a residencias", "loc_residencias", "por 100.000 hab. (promedio)", ambar),
      tarjeta_cifra("Hurto de motocicletas", "loc_motos", "por 100.000 hab. (promedio)", ambar)
    ),

    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Evolución del hurto: la localidad vs. el promedio de Bogotá"),
        radioButtons("modalidad_loc", NULL, choices = modalidades, inline = TRUE),
        plotlyOutput("grafico_evolucion", height = "320px")
      ),
      card(
        card_header("Tono de la prensa por año"),
        plotlyOutput("grafico_tono", height = "370px")
      )
    ),

    card(
      card_header("Qué dijo la prensa: las 5 noticias más negativas y las 5 más positivas"),
      DTOutput("tabla_noticias_loc")
    )
  ),

  ## 5.3 Pestaña 3: Hurto vs. prensa ----
  nav_panel(
    title = "Hurto vs. prensa", value = "prensa",
    h2(HTML(paste0(
      "¿La prensa sigue a las <span style='color:", ambar, "'>denuncias</span>, ",
      "o cuenta <span style='color:", azul, "'>otra historia</span>?"
    ))),

    layout_columns(
      col_widths = c(8, 4),
      card(
        card_header("Cada punto es una localidad · clic en un punto"),
        plotlyOutput("grafico_dispersion", height = "520px"),
        p("Tamaño del punto = número de noticias. Líneas punteadas = promedios.",
          style = paste0("color:", gris_texto, "; font-size: 13px"))
      ),
      div(
        card(
          card_header("Localidad seleccionada"),
          uiOutput("ficha_prensa")
        ),
        card(
          card_header("Filtros"),
          selectInput("anio_prensa", "Año", choices = opciones_anio),
          selectInput("modalidad_prensa", "Eje X: modalidad", choices = modalidades)
        ),
        card(
          card_header("Cómo leer el gráfico"),
          tags$ol(
            tags$li("Más a la derecha = más hurto denunciado."),
            tags$li("Más arriba = la prensa habla de esa localidad en tono más negativo."),
            tags$li("Las líneas punteadas dividen la ciudad en cuatro historias.")
          )
        )
      )
    )
  ),

  ## 5.4 Pestaña 4: Clusters ----
  nav_panel(
    title = "Clusters", value = "clusters",
    h2("Tres Bogotás según su hurto"),
    p("Agrupamos las 19 localidades con K-means según sus tres tasas de hurto.",
      style = paste0("color:", gris_texto)),
    radioButtons("grupo_resaltado", "Resaltar en el mapa",
                 choices = c("Todos", names(colores_cluster)), inline = TRUE),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Mapa de grupos"),
        leafletOutput("mapa_clusters", height = "520px")
      ),
      uiOutput("tarjetas_clusters")
    )
  ),

  ## 5.5 Pestaña 5: Datos y método ----
  nav_panel(
    title = "Datos y método", value = "metodo",
    card(
      card_header("De dónde salen los números"),
      tags$ul(
        tags$li("Hurtos: Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ)."),
        tags$li("Población: proyecciones de la Secretaría Distrital de Salud (SDS)."),
        tags$li("Noticias: Google News RSS. Sentimiento calculado con sentometrics
                 (Ardia et al., 2021) y léxicos en español."),
        tags$li("Grupos: K-means sobre las tres tasas de hurto estandarizadas.")
      ),
      p(strong("Advertencias: "),
        "2026 tiene datos solo hasta septiembre. Las tasas usan población residente,
         por eso las localidades del centro aparecen con tasas muy altas.")
    )
  )
)

# 6. Lógica del Servidor ----

server <- function(input, output, session) {

  ## 6.1 Pestaña 1: Panorama ----

  datos_panorama <- reactive({
    resumir_panel(input$anio)
  })

  output$kpi_tasa <- renderText({
    formato(mean(datos_panorama()[[input$modalidad]], na.rm = TRUE), 1)
  })

  output$kpi_noticias <- renderText({
    formato(sum(datos_panorama()$noticias_conteo, na.rm = TRUE))
  })

  output$kpi_sentimiento <- renderText({
    formato(mean(datos_panorama()$sentimiento_promedio, na.rm = TRUE), 3)
  })

  output$kpi_negativas <- renderText({
    paste0(formato(mean(datos_panorama()$prop_negativas, na.rm = TRUE), 1), " %")
  })

  output$mapa_panorama <- renderLeaflet({
    capa <- geo_localidades |>
      select(codigo_localidad, geometry) |>
      inner_join(datos_panorama(), by = "codigo_localidad")

    if (input$capa_mapa == "hurto") {
      valores <- capa[[input$modalidad]]
      pal     <- paleta_cuartiles(valores, c("#33281A", "#6E4A1C", "#B0731F", ambar))
      titulo  <- "Tasa por 100.000 hab."
    } else {
      valores <- capa[[input$medida]]
      pal     <- paleta_cuartiles(valores, c("#1B2638", "#2C3D5C", "#4F74B3", azul))
      titulo  <- names(medidas_prensa)[medidas_prensa == input$medida]
    }

    leaflet(capa) |>
      agregar_mapa_base() |>
      addPolygons(
        layerId     = ~localidad,
        fillColor   = pal(valores),
        fillOpacity = 0.85,
        color       = fondo,
        weight      = 1.5,
        label       = paste0(capa$localidad, ": ", formato(valores, 1)),
        highlightOptions = highlightOptions(weight = 3, color = "#E9EDF2",
                                            bringToFront = TRUE)
      ) |>
      addLegend(pal = pal, values = valores, title = titulo,
                position = "bottomright", opacity = 0.9)
  })

  # Clic en el mapa: abre la ficha de esa localidad
  observeEvent(input$mapa_panorama_shape_click, {
    updateSelectInput(session, "localidad", selected = input$mapa_panorama_shape_click$id)
    nav_select("pestanas", "localidad")
  })

  output$grafico_top5 <- renderPlotly({
    top5 <- datos_panorama() |>
      mutate(valor = .data[[input$modalidad]]) |>
      slice_max(valor, n = 5) |>
      arrange(valor)

    plot_ly(top5, x = ~valor, y = ~localidad, type = "bar", orientation = "h",
            marker = list(color = ambar),
            text = ~formato(valor), textposition = "outside", hoverinfo = "none") |>
      layout(yaxis = list(categoryorder = "array", categoryarray = top5$localidad)) |>
      estilo_plotly("Tasa por 100.000 hab.", "")
  })

  ## 6.2 Pestaña 2: Mi localidad ----

  datos_promedio <- resumir_panel("todos")   # promedio 2022-2026, no cambia

  # Puesto de la localidad (1 = la tasa más alta) en una modalidad
  puesto <- function(variable) {
    rank(-datos_promedio[[variable]])[datos_promedio$localidad == input$localidad]
  }

  valor_loc <- function(variable) {
    datos_promedio[[variable]][datos_promedio$localidad == input$localidad]
  }

  output$ficha_titulo <- renderUI({
    fila <- filter(datos_promedio, localidad == input$localidad)
    tagList(
      p(fila$cluster_nombre, style = paste0("color:", gris_texto, "; margin: 0")),
      h1(input$localidad, style = "font-weight: 800; margin: 4px 0"),
      p(HTML(paste0(
        "Tiene la <strong style='color:", ambar, "'>", puesto("tasa_hurto_personas"),
        ".ª</strong> tasa más alta de hurto a personas de las 19 localidades, con ",
        formato(fila$tasa_hurto_personas), " casos por 100.000 habitantes al año."
      )), style = "font-size: 18px")
    )
  })

  output$loc_personas <- renderText({
    paste0(formato(valor_loc("tasa_hurto_personas")),
           "  ·  puesto ", puesto("tasa_hurto_personas"), " de 19")
  })
  output$loc_residencias <- renderText({
    paste0(formato(valor_loc("tasa_hurto_residencias"), 1),
           "  ·  puesto ", puesto("tasa_hurto_residencias"), " de 19")
  })
  output$loc_motos <- renderText({
    paste0(formato(valor_loc("tasa_hurto_motos"), 1),
           "  ·  puesto ", puesto("tasa_hurto_motos"), " de 19")
  })

  output$grafico_evolucion <- renderPlotly({
    variable <- input$modalidad_loc

    serie_loc <- panel_localidades |>
      filter(localidad == input$localidad) |>
      transmute(año, valor = .data[[variable]])

    serie_bogota <- panel_localidades |>
      group_by(año) |>
      summarise(valor = mean(.data[[variable]], na.rm = TRUE), .groups = "drop")

    plot_ly() |>
      add_lines(data = serie_loc, x = ~año, y = ~valor, name = input$localidad,
                line = list(color = ambar, width = 3)) |>
      add_lines(data = serie_bogota, x = ~año, y = ~valor, name = "Promedio Bogotá",
                line = list(color = gris_texto, dash = "dash")) |>
      estilo_plotly("Año (2026 hasta septiembre)", "Tasa por 100.000 hab.")
  })

  output$grafico_tono <- renderPlotly({
    tono <- panel_localidades |>
      filter(localidad == input$localidad)

    plot_ly(tono, x = ~año, y = ~prop_negativas, type = "bar", name = "Negativas",
            marker = list(color = azul)) |>
      add_trace(y = ~prop_neutras, name = "Neutras", marker = list(color = "#3A4250")) |>
      add_trace(y = ~prop_positivas, name = "Positivas", marker = list(color = "#2C3D5C")) |>
      layout(barmode = "stack") |>
      estilo_plotly("Año", "% de noticias")
  })

  output$tabla_noticias_loc <- renderDT({
    noticias_loc <- tabla_noticias |>
      filter(localidad == input$localidad) |>
      arrange(sentimiento_score)

    extremos <- bind_rows(head(noticias_loc, 5), tail(noticias_loc, 5)) |>
      distinct(id, .keep_all = TRUE) |>
      transmute(
        Fecha     = as.character(fecha),
        Titular   = ifelse(!is.na(enlace) & enlace != "",
                           paste0("<a href='", enlace, "' target='_blank'>", titulo, "</a>"),
                           titulo),
        Medio     = fuente,
        Modalidad = delito_sdscj,
        Tono      = sentimiento_categoria
      )

    datatable(extremos, escape = FALSE, rownames = FALSE,
              options = list(dom = "t", pageLength = 10, scrollX = TRUE))
  })

  ## 6.3 Pestaña 3: Hurto vs. prensa ----

  datos_prensa <- reactive({
    resumir_panel(input$anio_prensa) |>
      mutate(eje_x = .data[[input$modalidad_prensa]])
  })

  # Localidad seleccionada con clic (empieza en Teusaquillo)
  localidad_prensa <- reactiveVal("Teusaquillo")

  observeEvent(event_data("plotly_click", source = "dispersion"), {
    clic <- event_data("plotly_click", source = "dispersion")
    localidad_prensa(clic$customdata)
  })

  output$grafico_dispersion <- renderPlotly({
    df <- datos_prensa()
    media_x <- mean(df$eje_x, na.rm = TRUE)
    media_y <- mean(df$prop_negativas, na.rm = TRUE)

    linea <- function(x0, x1, y0, y1) {
      list(type = "line", x0 = x0, x1 = x1, y0 = y0, y1 = y1,
           line = list(color = "#4A5363", dash = "dash"))
    }
    nota <- function(x, y, texto, color = gris_texto) {
      list(x = x, y = y, xref = "paper", yref = "paper", text = texto,
           showarrow = FALSE, font = list(color = color, size = 12))
    }

    plot_ly(
      df, x = ~eje_x, y = ~prop_negativas,
      type = "scatter", mode = "markers+text", source = "dispersion",
      color = ~cluster_nombre, colors = colores_cluster,
      size = ~noticias_conteo, sizes = c(12, 45),
      marker = list(line = list(color = fondo, width = 1), opacity = 0.9),
      text = ~localidad, textposition = "top center",
      textfont = list(color = "#C5CDD8", size = 11),
      customdata = ~localidad,
      hovertemplate = "<b>%{customdata}</b><br>Tasa: %{x:,.0f}<br>Negativas: %{y:.1f} %<extra></extra>"
    ) |>
      layout(
        shapes = list(
          linea(media_x, media_x, min(df$prop_negativas), max(df$prop_negativas)),
          linea(min(df$eje_x), max(df$eje_x), media_y, media_y)
        ),
        annotations = list(
          nota(0.02, 0.98, "<b>Poco hurto, prensa dura</b><br>¿estigma mediático?", azul),
          nota(0.98, 0.98, "Mucho hurto,<br>prensa dura"),
          nota(0.02, 0.02, "Poco hurto,<br>prensa tranquila"),
          nota(0.98, 0.02, "Mucho hurto,<br>prensa tranquila")
        )
      ) |>
      estilo_plotly(
        paste("Tasa de hurto a", tolower(names(modalidades)[modalidades == input$modalidad_prensa]),
              "(por 100.000 hab.)"),
        "% de noticias con tono negativo"
      ) |>
      event_register("plotly_click")
  })

  output$ficha_prensa <- renderUI({
    df   <- datos_prensa()
    fila <- filter(df, localidad == localidad_prensa())
    req(nrow(fila) == 1)

    mucho_hurto  <- fila$eje_x >= mean(df$eje_x, na.rm = TRUE)
    prensa_dura  <- fila$prop_negativas >= mean(df$prop_negativas, na.rm = TRUE)
    lectura <- case_when(
      mucho_hurto  & prensa_dura  ~ "Mucho hurto y prensa dura: la cobertura acompaña a las cifras.",
      mucho_hurto  & !prensa_dura ~ "Mucho hurto pero prensa más tranquila de lo esperado.",
      !mucho_hurto & prensa_dura  ~ "Poco hurto pero prensa dura: posible estigma mediático.",
      TRUE                        ~ "Poco hurto y prensa tranquila."
    )

    tagList(
      h3(fila$localidad, style = "font-weight: 800"),
      layout_columns(
        col_widths = c(6, 6),
        div(p("Tasa de hurto", style = paste0("color:", gris_texto, "; margin: 0")),
            h4(formato(fila$eje_x), style = paste0("color:", ambar))),
        div(p("Noticias negativas", style = paste0("color:", gris_texto, "; margin: 0")),
            h4(paste0(formato(fila$prop_negativas, 1), " %"), style = paste0("color:", azul)))
      ),
      div(lectura, style = "background: #232A35; padding: 10px; border-radius: 10px")
    )
  })

  ## 6.4 Pestaña 4: Clusters ----

  output$mapa_clusters <- renderLeaflet({
    capa <- geo_localidades |>
      select(codigo_localidad, geometry) |>
      inner_join(datos_promedio, by = "codigo_localidad")

    # Si se resalta un grupo, los demás se ven casi transparentes
    opacidad <- ifelse(input$grupo_resaltado == "Todos" |
                         capa$cluster_nombre == input$grupo_resaltado, 0.9, 0.15)

    leaflet(capa) |>
      agregar_mapa_base() |>
      addPolygons(
        fillColor   = colores_cluster[capa$cluster_nombre],
        fillOpacity = opacidad,
        color       = fondo,
        weight      = 1.5,
        label       = paste0(capa$localidad, " — ", capa$cluster_nombre)
      )
  })

  output$tarjetas_clusters <- renderUI({
    resumen <- datos_promedio |>
      group_by(cluster_nombre) |>
      summarise(
        n_localidades = n(),
        personas      = mean(tasa_hurto_personas),
        residencias   = mean(tasa_hurto_residencias),
        motos         = mean(tasa_hurto_motos),
        miembros      = paste(sort(localidad), collapse = ", "),
        .groups = "drop"
      ) |>
      arrange(desc(personas))

    tarjetas <- lapply(seq_len(nrow(resumen)), function(i) {
      g <- resumen[i, ]
      resaltada <- input$grupo_resaltado == g$cluster_nombre
      card(
        style = paste0("border: 2px solid ",
                       ifelse(resaltada, colores_cluster[g$cluster_nombre], borde)),
        card_header(
          span("●", style = paste0("color:", colores_cluster[g$cluster_nombre])),
          strong(g$cluster_nombre),
          span(paste(g$n_localidades, "localidades"),
               style = paste0("float: right; color:", gris_texto))
        ),
        layout_columns(
          col_widths = c(4, 4, 4),
          div(p("Personas", style = paste0("color:", gris_texto, "; margin: 0")),
              h4(formato(g$personas), style = paste0("color:", ambar))),
          div(p("Residencias", style = paste0("color:", gris_texto, "; margin: 0")),
              h4(formato(g$residencias, 1), style = paste0("color:", ambar))),
          div(p("Motos", style = paste0("color:", gris_texto, "; margin: 0")),
              h4(formato(g$motos, 1), style = paste0("color:", ambar)))
        ),
        p(g$miembros, style = paste0("color:", gris_texto, "; font-size: 13px"))
      )
    })

    tagList(tarjetas,
            p("Tasas promedio del grupo, por 100.000 habitantes al año.",
              style = paste0("color:", gris_texto, "; font-size: 12px")))
  })
}

# 7. Ejecución de la App ----
shinyApp(ui = ui, server = server)
