# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: app/app.R
# ROL: App Shiny "Bogo-Atrack" (Observatorio de hurto y sentimiento mediático)
# AUTORA: Olga Lucía Ramírez — Grupo 10 (Juan José Echeverry, Sergio López,
#         Miguelangel Palma, Gabriel Echeverry, Juan Esteban Carvajal)
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
#   1. Panorama                  -> cifras clave, mapa y ranking
#   2. Mi localidad              -> ficha detallada de una localidad
#   3. Hurto vs. prensa          -> gráfico de dispersión (la pregunta del proyecto)
#   4. Clusters                  -> los 3 grupos territoriales de K-means
#   5. Sentometrics y Elastic Net-> series mensuales (L×F×T), peakdates y atribuciones
#   6. Datos y método            -> fuentes, fórmulas y contrato de artefactos .rds

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----
library(shiny)
library(bslib)
library(here)
library(conflicted)
library(dplyr)
library(tidyr)
library(stringr)
library(plotly)
library(DT)
library(leaflet)
library(sf)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("layout", "plotly", quiet = TRUE)

# 2. Carga de Datos y Pre-cálculo Global ----

## 2.1 Lectura y validación del bundle consolidado ----
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
peakdates_neg     <- as.Date(datos_app$global_index$peakdates_neg)   # picos negativos
peakdates_pos     <- as.Date(datos_app$global_index$peakdates_pos)   # picos positivos
attr_long_raw     <- as_tibble(datos_app$attributions$attr_long_raw) # atribuciones crudas
attr_long_norm    <- as_tibble(datos_app$attributions$attr_long_norm)# atribuciones norm.
ajuste_temporal   <- as_tibble(datos_app$attributions$ajuste_temporal)
coeficientes_df   <- as_tibble(datos_app$attributions$coeficientes)
metricas_modelo   <- datos_app$attributions$metricas_modelo

# Control de auditoría: verificar las 19 localidades urbanas
stopifnot(length(unique(panel_localidades$codigo_localidad)) == 19)

## 2.2 Listas, catálogos y paleta cromática global ----
lista_localidades <- sort(unique(panel_localidades$localidad))

modalidades <- c(
  "Total"        = "tasa_hurto_total",
  "Personas"     = "tasa_hurto_personas",
  "Residencias"  = "tasa_hurto_residencias",
  "Motocicletas" = "tasa_hurto_motos"
)

mapa_modalidad_noticia <- c(
  "tasa_hurto_personas"    = "Hurto a personas",
  "tasa_hurto_residencias" = "Hurto a residencias",
  "tasa_hurto_motos"       = "Hurto de motocicletas"
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

lista_esquemas_tiempo <- sort(unique(measures_long$time))
names(lista_esquemas_tiempo) <- case_when(
  lista_esquemas_tiempo == "linear"         ~ "Lineal (memoria uniforme en 6 meses)",
  lista_esquemas_tiempo == "exponential0.5" ~ "Exponencial (α = 0,5 · foco reciente)",
  lista_esquemas_tiempo == "beta22"         ~ "Beta (2, 2 · pico intermedio)",
  TRUE                                      ~ lista_esquemas_tiempo
)

colores_cluster <- c(
  "Céntrico e Institucional" = "#B08CF0",
  "Comercial y Automotor"    = "#E86A50",
  "Residencial y Periférico" = "#3FB8A6"
)

colores_cluster_iluminado <- c(
  "Céntrico e Institucional" = "#E2CCFF",
  "Comercial y Automotor"    = "#FF9E85",
  "Residencial y Periférico" = "#75FFF0"
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
resumir_panel <- function(anio, modalidad = "tasa_hurto_total") {
  if (anio == "todos") {
    base_tasas <- panel_localidades |>
      group_by(codigo_localidad, localidad, cluster_nombre, silueta_localidad) |>
      summarise(
        tasa_hurto_personas    = mean(tasa_hurto_personas, na.rm = TRUE),
        tasa_hurto_residencias = mean(tasa_hurto_residencias, na.rm = TRUE),
        tasa_hurto_motos       = mean(tasa_hurto_motos, na.rm = TRUE),
        tasa_hurto_total       = mean(tasa_hurto_total, na.rm = TRUE),
        noticias_conteo        = sum(noticias_conteo, na.rm = TRUE),
        sentimiento_promedio   = mean(sentimiento_promedio, na.rm = TRUE),
        prop_negativas         = mean(prop_negativas, na.rm = TRUE),
        .groups = "drop"
      )
  } else {
    base_tasas <- panel_localidades |>
      filter(año == as.integer(anio))
  }

  # Si se selecciona una modalidad específica, filtramos las métricas de prensa por esa modalidad
  if (!is.null(modalidad) && modalidad %in% names(mapa_modalidad_noticia)) {
    noticias_filtradas <- tabla_noticias |>
      filter(delito_sdscj == unname(mapa_modalidad_noticia[modalidad]))

    if (anio != "todos") {
      noticias_filtradas <- noticias_filtradas |>
        filter(año == as.integer(anio))
    }

    prensa_mod <- noticias_filtradas |>
      group_by(localidad) |>
      summarise(
        noticias_conteo      = n(),
        sentimiento_promedio = round(mean(sentimiento_score, na.rm = TRUE), 4),
        prop_negativas       = round(mean(sentimiento_categoria == "Negativo", na.rm = TRUE) * 100, 2),
        .groups = "drop"
      )

    base_tasas <- base_tasas |>
      select(-noticias_conteo, -sentimiento_promedio, -prop_negativas) |>
      left_join(prensa_mod, by = "localidad") |>
      mutate(
        noticias_conteo      = replace_na(noticias_conteo, 0L),
        sentimiento_promedio = replace_na(sentimiento_promedio, 0),
        prop_negativas       = replace_na(prop_negativas, 0)
      )
  }

  base_tasas
}

# Pre-cálculo del panel promedio 2022-2026 (constante entre sesiones)
datos_promedio_global <- resumir_panel("todos", "tasa_hurto_total")

## 3.2b Pre-cálculo global de coordenadas 3D (tasas reales y Z-score) ----
preparar_datos_clusters_3d <- function(df_clusters) {
  df_base <- df_clusters |>
    mutate(
      z_pers  = as.numeric(scale(tasa_personas_prom)),
      z_resid = as.numeric(scale(tasa_resid_prom)),
      z_motos = as.numeric(scale(tasa_motos_prom)),
      tooltip_loc = paste0(
        "<b>", localidad, "</b><br>",
        "Clúster: ", cluster_nombre, "<br>",
        "Hurto personas: ", formato(tasa_personas_prom, 1), " / 100k hab. (Z = ", formato(z_pers, 2), ")<br>",
        "Hurto residencias: ", formato(tasa_resid_prom, 1), " / 100k hab. (Z = ", formato(z_resid, 2), ")<br>",
        "Hurto motos: ", formato(tasa_motos_prom, 1), " / 100k hab. (Z = ", formato(z_motos, 2), ")<br>",
        "Silueta S(i): ", formato(silueta_localidad, 3)
      )
    )

  centroides <- df_base |>
    group_by(cluster_nombre) |>
    summarise(
      cx_tasa = mean(tasa_personas_prom),
      cy_tasa = mean(tasa_resid_prom),
      cz_tasa = mean(tasa_motos_prom),
      cx_z    = mean(z_pers),
      cy_z    = mean(z_resid),
      cz_z    = mean(z_motos),
      sil_med = mean(silueta_localidad, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      tooltip_cen = paste0(
        "<b>★ Centroide μ_k: ", cluster_nombre, "</b><br>",
        "Media personas: ", formato(cx_tasa, 1), " / 100k hab. (Z = ", formato(cx_z, 2), ")<br>",
        "Media residencias: ", formato(cy_tasa, 1), " / 100k hab. (Z = ", formato(cy_z, 2), ")<br>",
        "Media motos: ", formato(cz_tasa, 1), " / 100k hab. (Z = ", formato(cz_z, 2), ")<br>",
        "Silueta media: ", formato(sil_med, 3)
      )
    )

  puntos <- df_base |>
    left_join(
      centroides |> select(cluster_nombre, cx_tasa, cy_tasa, cz_tasa, cx_z, cy_z, cz_z),
      by = "cluster_nombre"
    )

  segmentos <- bind_rows(lapply(seq_len(nrow(puntos)), function(i) {
    fila <- puntos[i, ]
    tibble(
      x_tasa = c(fila$tasa_personas_prom, fila$cx_tasa, NA_real_),
      y_tasa = c(fila$tasa_resid_prom,    fila$cy_tasa, NA_real_),
      z_tasa = c(fila$tasa_motos_prom,    fila$cz_tasa, NA_real_),
      x_z    = c(fila$z_pers,             fila$cx_z,    NA_real_),
      y_z    = c(fila$z_resid,            fila$cy_z,    NA_real_),
      z_z    = c(fila$z_motos,            fila$cz_z,    NA_real_),
      cluster_nombre = fila$cluster_nombre
    )
  }))

  empaquetar_escala <- function(sufijo) {
    col_p <- if (sufijo == "z") c("z_pers", "z_resid", "z_motos") else c("tasa_personas_prom", "tasa_resid_prom", "tasa_motos_prom")
    pts_sub <- tibble(
      x = puntos[[col_p[1]]], y = puntos[[col_p[2]]], z = puntos[[col_p[3]]],
      localidad = puntos$localidad, cluster_nombre = puntos$cluster_nombre,
      tooltip_loc = puntos$tooltip_loc
    )
    cen_sub <- tibble(
      x = centroides[[paste0("cx_", sufijo)]],
      y = centroides[[paste0("cy_", sufijo)]],
      z = centroides[[paste0("cz_", sufijo)]],
      cluster_nombre = centroides$cluster_nombre,
      tooltip_cen    = centroides$tooltip_cen
    )
    seg_sub <- tibble(
      x = segmentos[[paste0("x_", sufijo)]],
      y = segmentos[[paste0("y_", sufijo)]],
      z = segmentos[[paste0("z_", sufijo)]],
      cluster_nombre = segmentos$cluster_nombre
    )
    list(
      puntos     = split(pts_sub, pts_sub$cluster_nombre),
      centroides = split(cen_sub, cen_sub$cluster_nombre),
      segmentos  = split(seg_sub, seg_sub$cluster_nombre)
    )
  }

  list(
    tasas  = empaquetar_escala("tasa"),
    zscore = empaquetar_escala("z")
  )
}

datos_clusters_3d <- preparar_datos_clusters_3d(clusters_perfiles)

## 3.3 Paleta de 4 niveles (cuartiles) para los mapas ----
paleta_cuartiles <- function(valores, colores) {
  rango <- range(valores, na.rm = TRUE)
  if (!all(is.finite(rango)) || rango[1] == rango[2]) {
    val_unico <- ifelse(is.finite(rango[1]), rango[1], 0)
    cortes <- seq(val_unico - 1, val_unico + 1, length.out = 5)
    return(colorBin(colores, domain = c(val_unico - 1, val_unico + 1), bins = cortes))
  }

  cortes <- unique(quantile(valores, probs = seq(0, 1, 0.25), na.rm = TRUE))
  if (length(cortes) < 5) {
    cortes <- seq(rango[1], rango[2], length.out = 5)
  }
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

## 4.1 Definición del tema bslib Bootstrap 5 ----
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
  id           = "pestanas",
  window_title = "Bogo-Atrack · Observatorio de hurto y sentimiento mediático",
  title        = tags$div(
    class = "d-flex flex-column",
    style = paste0(
      "line-height: 1.15; padding: 2px 20px 2px 0; ",
      "margin-right: 6px; border-right: 1px solid ", borde, ";"
    ),
    tags$span(
      "Bogo-Atrack",
      style = "font-weight: 800; font-size: 1.08rem; letter-spacing: -0.01em;"
    ),
    tags$span(
      "Observatorio de hurto y sentimiento mediático",
      style = paste0("font-size: 0.68rem; font-weight: 400; color:", gris_texto, ";")
    )
  ),
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
      .header-3d-switches .form-check,
      .header-3d-switches .shiny-input-container {
        margin-bottom: 0 !important;
      }
      .header-3d-switches .form-check-label {
        font-size: 0.875rem;
        color: #C5CDD8;
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
                    "3 modalidades objetivo · Google News", azul),
      tarjeta_cifra("Sentimiento neto promedio", "kpi_sentimiento",
                    "sentometrics", azul),
      tarjeta_cifra("Noticias con tono negativo", "kpi_negativas",
                    "promedio de las localidades", azul)
    ),

    layout_columns(
      col_widths = c(8, 4),
      card(
        card_header(textOutput("titulo_mapa_panorama", inline = TRUE)),
        leafletOutput("mapa_panorama", height = "480px")
      ),
      card(
        card_header(textOutput("titulo_top5_panorama", inline = TRUE)),
        plotlyOutput("grafico_top5", height = "300px"),
        p(textOutput("nota_top5_panorama", inline = TRUE),
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
      col_widths = c(3, 3, 3, 3),
      tarjeta_cifra("Hurto total", "loc_total", "por 100.000 hab. (promedio)", ambar),
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
      div(
        card(
          card_header("Cada punto es una localidad · clic en un punto"),
          plotlyOutput("grafico_dispersion", height = "520px"),
          p("Tamaño del punto = número de noticias. Líneas punteadas = promedios distritales.",
            style = paste0("color:", gris_texto, "; font-size: 13px"))
        ),
        card(
          card_header("¿Por qué se dividió así el gráfico y cómo se especificaron las líneas de corte?"),
          uiOutput("explicacion_lineas_corte"),
          hr(style = paste0("border-color:", borde, "; margin: 10px 0")),
          p(strong("1. ¿Cómo se especificaron las líneas de corte?"),
            style = "margin-bottom: 4px"),
          p(
            "Las dos líneas punteadas no son umbrales arbitrarios fijos: corresponden exactamente al ",
            strong("promedio simple distrital de las 19 localidades urbanas"),
            " en el año y la modalidad seleccionados:",
            style = paste0("color:", gris_texto, "; font-size: 13.5px; margin-bottom: 6px")
          ),
          tags$ul(
            style = paste0("color:", gris_texto, "; font-size: 13.5px; margin-bottom: 10px"),
            tags$li(
              HTML(paste0(
                "<strong style='color:", ambar, "'>Corte vertical (X̄):</strong> media de la tasa de hurto denunciado por cada 100.000 habitantes entre las 19 localidades. Divide la ciudad entre localidades con presión delictiva per cápita <em>por debajo</em> (izquierda) y <em>por encima</em> (derecha) del promedio de Bogotá."
              ))
            ),
            tags$li(
              HTML(paste0(
                "<strong style='color:", azul, "'>Corte horizontal (Ȳ):</strong> media del porcentaje de noticias con tono negativo (puntaje <code>sentometrics &lt; 0</code>) entre las 19 localidades. Separa la cobertura periodística <em>más moderada que el promedio</em> (abajo) de la <em>más severa o alarmante que el promedio</em> (arriba)."
              ))
            )
          ),
          p(strong("2. ¿Por qué se dividió así y qué significa esta partición?"),
            style = "margin-bottom: 4px"),
          p(
            "El propósito central del estudio es contrastar las «dos lecturas» de la inseguridad: la incidencia estadística oficial (SIEDCO) frente a la amplificación mediática (Google News). Si la prensa reflejara de manera estrictamente proporcional las tasas de denuncia, todas las localidades se alinearían sobre una diagonal entre el cuadrante inferior izquierdo y el superior derecho. Al cruzar ambos promedios (X̄, Ȳ), el plano queda dividido en ",
            strong("cuatro cuadrantes o historias urbanas"),
            " que permiten identificar dónde coinciden ambas lecturas y dónde existe desajuste:",
            style = paste0("color:", gris_texto, "; font-size: 13.5px; margin-bottom: 8px")
          ),
          layout_columns(
            col_widths = c(6, 6),
            div(
              style = "background: #232A35; padding: 10px 12px; border-radius: 8px; border-left: 3px solid #79AEFF; margin-bottom: 6px",
              p(strong("↖ Poco hurto relativo, prensa dura (X < X̄, Y ≥ Ȳ)"),
                style = paste0("color:", azul, "; margin: 0 0 4px 0; font-size: 13px")),
              p("Posible sobre-exposición o estigma mediático: la tasa por 100.000 hab. es menor al promedio distrital, pero la prensa concentra titulares de alta negatividad (frecuente en localidades periféricas muy pobladas donde los medios cubren casos violentos por volumen absoluto sin ponderar por población).",
                style = paste0("color:", gris_texto, "; margin: 0; font-size: 12.5px"))
            ),
            div(
              style = "background: #232A35; padding: 10px 12px; border-radius: 8px; border-left: 3px solid #F0A43A; margin-bottom: 6px",
              p(strong("↗ Mucho hurto, prensa dura (X ≥ X̄, Y ≥ Ȳ)"),
                style = paste0("color:", ambar, "; margin: 0 0 4px 0; font-size: 13px")),
              p("Convergencia de lecturas: localidades céntricas y comerciales con alta tasa de denuncias por habitante donde el tono negativo de la prensa acompaña la magnitud estadística del delito.",
                style = paste0("color:", gris_texto, "; margin: 0; font-size: 12.5px"))
            ),
            div(
              style = "background: #232A35; padding: 10px 12px; border-radius: 8px; border-left: 3px solid #3FB8A6",
              p(strong("↙ Poco hurto, prensa tranquila (X < X̄, Y < Ȳ)"),
                style = "color: #3FB8A6; margin: 0 0 4px 0; font-size: 13px"),
              p("Baja presión en ambas dimensiones: tanto la tasa de denuncias per cápita como la proporción de noticias negativas se sitúan por debajo del promedio de Bogotá.",
                style = paste0("color:", gris_texto, "; margin: 0; font-size: 12.5px"))
            ),
            div(
              style = "background: #232A35; padding: 10px 12px; border-radius: 8px; border-left: 3px solid #9AA4B2",
              p(strong("↘ Mucho hurto, prensa tranquila (X ≥ X̄, Y < Ȳ)"),
                style = "color: #E9EDF2; margin: 0 0 4px 0; font-size: 13px"),
              p("Sub-cobertura relativa o normalización del delito: registra tasas de hurto superiores a la media distrital, pero el tono periodístico es menos negativo que el promedio de la ciudad.",
                style = paste0("color:", gris_texto, "; margin: 0; font-size: 12.5px"))
            )
          )
        )
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
            tags$li("Las líneas punteadas (X̄, Ȳ) dividen la ciudad en cuatro historias según el promedio distrital.")
          )
        )
      )
    )
  ),

  ## 5.4 Pestaña 4: Clusters ----
  nav_panel(
    title = "Clusters", value = "clusters",
    h2("Tres Bogotás según su hurto"),
    p("Agrupamos las 19 localidades con K-means según sus tres tasas de hurto. Pasa el cursor sobre el mapa o el cubo 3D para ver los detalles de cada localidad, o haz clic en un grupo para iluminarlo.",
      style = paste0("color:", gris_texto)),
    radioButtons("grupo_resaltado", "Resaltar en el mapa y en 3D",
                 choices = c("Todos", names(colores_cluster)), inline = TRUE),
    layout_columns(
      col_widths = c(6, 6),
      card(
        full_screen = TRUE,
        card_header("Mapa de grupos · pasa el cursor para ver el coeficiente de silueta o haz clic para iluminar"),
        leafletOutput("mapa_clusters", height = "520px")
      ),
      uiOutput("tarjetas_clusters")
    ),
    card(
      id = "card_clusters_3d",
      full_screen = TRUE,
      card_header(
        class = "d-flex justify-content-between align-items-center flex-wrap gap-2 header-3d-switches",
        div(
          class = "d-flex align-items-center gap-2",
          span("Espacio tridimensional de clústeres K-Means (K* = 3)"),
          tooltip(
            tags$span(
              style = paste0(
                "display:inline-flex; align-items:center; justify-content:center; ",
                "width:18px; height:18px; border-radius:50%; border:1px solid ", gris_texto,
                "; color:", gris_texto, "; font-size:11px; font-weight:700; cursor:help;"
              ),
              tabindex = "0",
              role = "img",
              `aria-label` = "Ayuda sobre el gráfico tridimensional de clústeres",
              "?"
            ),
            "Cada esfera representa una localidad unida por su radio al diamante del centroide μ_k. Arrastra para rotar el cubo, usa la rueda para hacer zoom o haz clic en una esfera/diamante para resaltar su grupo."
          )
        ),
        div(
          class = "d-flex align-items-center flex-wrap gap-3",
          input_switch("mostrar_nombres_3d", "Mostrar nombres", value = TRUE),
          input_switch("escala_z_3d", "Escala Z-score", value = FALSE)
        )
      ),
      card_body(
        min_height = "560px",
        plotlyOutput("grafico_clusters_3d", height = "580px")
      ),
      card_footer(
        style = paste0("color:", gris_texto, "; font-size: 12px;"),
        "Esferas: 19 localidades · Diamantes: centroides μ_k · Líneas: radios intra-clúster. Cambia a Escala Z-score para ver el espacio estandarizado exacto en el que opera K-means."
      )
    )
  ),

  ## 5.5 Pestaña 5: Sentometrics y Elastic Net ----
  nav_panel(
    title = "Sentometrics y Elastic Net", value = "sentometrics",
    h2(HTML(paste0(
      "De los titulares al modelo: <span style='color:", azul, "'>Sentometrics</span> ",
      "y <span style='color:", ambar, "'>Elastic Net</span>"
    ))),
    p("36 series mensuales de sentimiento (6 features × 2 léxicos × 3 esquemas temporales, 993 noticias objetivo) frente a la tasa mensual real SIEDCO.",
      style = paste0("color:", gris_texto)),

    layout_columns(
      col_widths = c(3, 3, 3, 3),
      tarjeta_cifra("Bondad de ajuste (R²)", "kpi_r2_modelo",
                    "varianza mensual explicada (h = 1 mes)", ambar),
      tarjeta_cifra("Calibración Elastic Net (BIC)", "kpi_hiper_modelo",
                    "mezcla L1/L2 y penalización óptima", azul),
      tarjeta_cifra("Series seleccionadas (β ≠ 0)", "kpi_activos_modelo",
                    "de las 36 series candidatas", azul),
      tarjeta_cifra("Error cuadrático medio (RMSE)", "kpi_rmse_modelo",
                    "puntos de tasa mensual real sobre 51 meses", ambar)
    ),

    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header("Filtros de series mensuales (sento_measures)"),
        selectInput(
          "grupo_serie_sento",
          "1. Grupo de features",
          choices = c(
            "Clústeres Territoriales (3)" = "Clúster Territorial",
            "Modalidades de Hurto (3)"    = "Modalidad de Hurto"
          ),
          selected = "Clúster Territorial"
        ),
        uiOutput("selector_features_sento"),
        radioButtons(
          "lexico_sento",
          "3. Diccionario léxico",
          choices = c(
            "Crimen Bogotá (crimen_es)" = "crimen_es",
            "NRC Español (nrc_es)"      = "nrc_es"
          ),
          selected = "crimen_es",
          inline   = TRUE
        ),
        selectInput(
          "tiempo_sento",
          "4. Esquema de memoria temporal (lag = 6 meses)",
          choices  = lista_esquemas_tiempo,
          selected = "exponential0.5"
        ),
        checkboxInput(
          "ver_picos_sento",
          "Marcar meses críticos de alarma (peakdates)",
          value = TRUE
        )
      ),
      card(
        card_header("Evolución mensual de las series de sentimiento y fechas pico (peakdates)"),
        plotlyOutput("grafico_series_sento", height = "410px"),
        p("Las líneas verticales punteadas señalan los 8 meses de mayor negatividad detectados con sentometrics::peakdates().",
          style = paste0("color:", gris_texto, "; font-size: 13px"))
      )
    ),

    layout_columns(
      col_widths = c(7, 5),
      card(
        card_header("¿Qué empuja la predicción cada mes? · Atribuciones de Elastic Net (attributions)"),
        layout_columns(
          col_widths = c(7, 5),
          selectInput(
            "dim_attr_sento",
            "Descomponer por dimensión",
            choices = c(
              "Clústeres K-Means (3)"              = "clusters",
              "Modalidades de Hurto (3)"           = "temas",
              "Diccionarios (nrc_es vs crimen_es)" = "lexicons",
              "Esquemas de memoria (Time)"         = "time"
            ),
            selected = "clusters"
          ),
          radioButtons(
            "escala_attr_sento",
            "Escala",
            choices = c("Bruta" = "raw", "Normalizada [-1,1]" = "norm"),
            selected = "raw",
            inline   = TRUE
          )
        ),
        plotlyOutput("grafico_atribuciones_sento", height = "360px")
      ),
      card(
        card_header("Tasa mensual real SIEDCO (ámbar) vs. predicha por Elastic Net (azul)"),
        plotlyOutput("grafico_ajuste_sento", height = "220px"),
        p(strong("Top 10 series con mayor magnitud en el modelo (|β|):"),
          style = paste0("color:", gris_texto, "; margin: 8px 0 4px 0; font-size: 13px")),
        plotlyOutput("grafico_coefs_sento", height = "210px")
      )
    )
  ),

  ## 5.6 Pestaña 6: Datos y método ----
  nav_panel(
    title = "Datos y método", value = "metodo",
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("De dónde salen los números"),
        tags$ul(
          tags$li("Hurtos: microdatos mensuales oficiales SIEDCO del Observatorio SCJ (376.185 registros en 1.083 observaciones localidad × mes, ene. 2022–sep. 2026) en las tres modalidades objetivo: hurto a personas, residencias y motocicletas."),
          tags$li("Población: proyecciones demográficas de la Secretaría Distrital de Salud (SDS) para expresar todas las cifras por cada 100.000 habitantes."),
          tags$li("Noticias: Google News RSS (3.916 noticias recopiladas ene. 2022–sep. 2026), filtradas estrictamente a 993 noticias comparables de las 3 modalidades objetivo de hurto (736 personas, 141 residencias y 116 motocicletas)."),
          tags$li("Sentimiento: calculado con sentometrics (Ardia et al., 2021) usando 2 léxicos en español (nrc_es y crimen_es), modificadores de valencia (negadores, amplificadores, atenuadores y adversativos), 6 features binarias (3 clústeres + 3 modalidades) y 3 esquemas temporales en ventana de 6 meses (linear, exponential0.5 y beta22) = 36 series."),
          tags$li("Grupos territoriales: K-means (K* = 3, partición 13 / 5 / 1 validada por silueta y ARI = 1 con AGNES) sobre las tres tasas estandarizadas (Z-score)."),
          tags$li("Modelo econométrico: regresión penalizada Elastic Net (calibrada vía BIC, h = 1 mes) directamente contra la tasa mensual empírica de SIEDCO, más descomposición aditiva con attributions().")
        ),
        p(strong("Advertencias metodológicas: "),
          "2026 tiene datos con corte a septiembre. Las tasas usan población residente (DANE/SDS),
           por eso las localidades céntricas y comerciales con alta población flotante registran tasas mucho más altas.")
      ),
      card(
        card_header("Contrato de artefactos del pipeline (.rds)"),
        DTOutput("tabla_contrato_rds")
      )
    )
  )
)

# 6. Lógica del Servidor ----

server <- function(input, output, session) {

  ## 6.1 Pestaña 1: Panorama ----

  datos_panorama <- reactive({
    resumir_panel(input$anio, input$modalidad)
  }) |>
    bindCache(input$anio, input$modalidad)

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

  capa_panorama <- reactive({
    df           <- datos_panorama()
    etiqueta_mod <- names(modalidades)[modalidades == input$modalidad]

    if (input$capa_mapa == "hurto") {
      columna     <- input$modalidad
      valores     <- df[[columna]]
      colores_pal <- c("#33281A", "#6E4A1C", "#B0731F", ambar)
      digitos_lbl <- ifelse(input$modalidad %in% c("tasa_hurto_personas", "tasa_hurto_total"), 0, 1)
      titulo_ley  <- paste0("Tasa (", etiqueta_mod, ") / 100k hab.")
      titulo_mapa <- "¿Dónde se concentra el hurto? · clic en una localidad para ver su ficha"
      titulo_top5 <- paste0("Las 5 tasas más altas (", etiqueta_mod, ")")
      eje_x_top5  <- "Tasa por 100.000 hab."
      nota_top5   <- "Ojo: la tasa usa población residente. El centro recibe cada día trabajadores y visitantes de toda la ciudad, así que su tasa se infla."
      sufijo_txt  <- ""
    } else {
      columna      <- input$medida
      valores      <- df[[columna]]
      colores_pal  <- c("#1B2638", "#2C3D5C", "#4F74B3", azul)
      etiqueta_med <- names(medidas_prensa)[medidas_prensa == input$medida]
      digitos_lbl  <- case_when(
        input$medida == "noticias_conteo"      ~ 0,
        input$medida == "sentimiento_promedio" ~ 3,
        TRUE                                   ~ 1
      )
      titulo_ley  <- paste0(etiqueta_med, " (", etiqueta_mod, ")")
      titulo_mapa <- paste0("Cobertura de prensa: ", etiqueta_med, " (", etiqueta_mod, ") · clic en una localidad para ver su ficha")
      titulo_top5 <- case_when(
        input$medida == "prop_negativas"       ~ paste0("Las 5 con mayor % negativo (", etiqueta_mod, ")"),
        input$medida == "sentimiento_promedio" ~ paste0("Las 5 con sentimiento más alto (", etiqueta_mod, ")"),
        TRUE                                   ~ paste0("Las 5 con más noticias (", etiqueta_mod, ")")
      )
      eje_x_top5  <- etiqueta_med
      nota_top5   <- "Las localidades siguen los mismos tonos azules del mapa (el tono más claro marca los valores más altos). En subgrupos con pocas notas, 1 o 2 noticias mueven fuerte el porcentaje o el promedio."
      sufijo_txt  <- ifelse(input$medida == "prop_negativas", " %", "")
    }

    list(
      columna        = columna,
      paleta         = paleta_cuartiles(valores, colores_pal),
      colores_pal    = colores_pal,
      digitos        = digitos_lbl,
      titulo_leyenda = titulo_ley,
      titulo_mapa    = titulo_mapa,
      titulo_top5    = titulo_top5,
      eje_x_top5     = eje_x_top5,
      nota_top5      = nota_top5,
      sufijo_txt     = sufijo_txt
    )
  })

  output$titulo_mapa_panorama <- renderText({ capa_panorama()$titulo_mapa })
  output$titulo_top5_panorama <- renderText({ capa_panorama()$titulo_top5 })
  output$nota_top5_panorama   <- renderText({ capa_panorama()$nota_top5 })

  output$mapa_panorama <- renderLeaflet({
    cfg  <- capa_panorama()
    capa <- geo_localidades |>
      select(codigo_localidad, geometry) |>
      inner_join(datos_panorama(), by = "codigo_localidad")

    valores <- capa[[cfg$columna]]
    pal     <- cfg$paleta

    leaflet(capa) |>
      agregar_mapa_base() |>
      addPolygons(
        layerId     = ~localidad,
        fillColor   = pal(valores),
        fillOpacity = 0.85,
        color       = fondo,
        weight      = 1.5,
        label       = paste0(capa$localidad, ": ", formato(valores, cfg$digitos), cfg$sufijo_txt),
        highlightOptions = highlightOptions(weight = 3, color = "#E9EDF2",
                                            bringToFront = TRUE)
      ) |>
      addLegend(pal = pal, values = valores, title = cfg$titulo_leyenda,
                position = "bottomright", opacity = 0.9)
  })

  # Clic en el mapa: abre la ficha de esa localidad
  observeEvent(input$mapa_panorama_shape_click, {
    updateSelectInput(session, "localidad", selected = input$mapa_panorama_shape_click$id)
    nav_select("pestanas", "localidad")
  })

  output$grafico_top5 <- renderPlotly({
    cfg  <- capa_panorama()
    top5 <- datos_panorama() |>
      mutate(valor = .data[[cfg$columna]]) |>
      arrange(desc(valor), desc(noticias_conteo), localidad) |>
      slice_head(n = 5) |>
      arrange(valor)

    r_x <- range(c(0, top5$valor), na.rm = TRUE)
    amplitud <- diff(r_x)
    if (!is.finite(amplitud) || amplitud == 0) amplitud <- 1
    izq_pad <- if (r_x[1] < 0) r_x[1] - amplitud * 0.30 else 0
    der_pad <- if (r_x[2] > 0) r_x[2] + amplitud * 0.25 else amplitud * 0.08

    plot_ly(
      top5,
      x = ~valor, y = ~localidad, type = "bar", orientation = "h",
      marker = list(color = cfg$paleta(top5$valor), opacity = 0.88),
      text = ~paste0(formato(valor, cfg$digitos), cfg$sufijo_txt),
      textposition = "outside",
      cliponaxis = FALSE,
      hoverinfo = "none"
    ) |>
      layout(
        margin = list(r = 16),
        xaxis  = list(range = c(izq_pad, der_pad)),
        yaxis  = list(categoryorder = "array", categoryarray = top5$localidad)
      ) |>
      estilo_plotly(cfg$eje_x_top5, "")
  })

  ## 6.2 Pestaña 2: Mi localidad ----

  # Puesto de la localidad (1 = la tasa más alta) en una modalidad
  puesto <- function(variable) {
    rank(-datos_promedio_global[[variable]])[datos_promedio_global$localidad == input$localidad]
  }

  valor_loc <- function(variable) {
    datos_promedio_global[[variable]][datos_promedio_global$localidad == input$localidad]
  }

  output$ficha_titulo <- renderUI({
    fila <- filter(datos_promedio_global, localidad == input$localidad)
    tagList(
      p(fila$cluster_nombre, style = paste0("color:", gris_texto, "; margin: 0")),
      h1(input$localidad, style = "font-weight: 800; margin: 4px 0"),
      p(HTML(paste0(
        "Ocupa el <strong style='color:", ambar, "'>puesto ", puesto("tasa_hurto_total"),
        " de 19</strong> en hurto total consolidado, con ",
        formato(fila$tasa_hurto_total), " casos por 100.000 habitantes al año (",
        formato(fila$tasa_hurto_personas), " a personas, ",
        formato(fila$tasa_hurto_residencias, 1), " a residencias y ",
        formato(fila$tasa_hurto_motos, 1), " de motocicletas)."
      )), style = "font-size: 18px")
    )
  })

  output$loc_total <- renderText({
    paste0(formato(valor_loc("tasa_hurto_total")),
           "  ·  puesto ", puesto("tasa_hurto_total"), " de 19")
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
    resumir_panel(input$anio_prensa, input$modalidad_prensa) |>
      mutate(eje_x = .data[[input$modalidad_prensa]])
  }) |>
    bindCache(input$anio_prensa, input$modalidad_prensa)

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

    titulo_eje_x <- if (input$modalidad_prensa == "tasa_hurto_total") {
      "Tasa de hurto total (por 100.000 hab.)"
    } else {
      paste("Tasa de hurto a", tolower(names(modalidades)[modalidades == input$modalidad_prensa]),
            "(por 100.000 hab.)")
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
        titulo_eje_x,
        "% de noticias con tono negativo"
      ) |>
      event_register("plotly_click")
  })

  output$explicacion_lineas_corte <- renderUI({
    df      <- datos_prensa()
    media_x <- mean(df$eje_x, na.rm = TRUE)
    media_y <- mean(df$prop_negativas, na.rm = TRUE)
    etiqueta_mod  <- names(modalidades)[modalidades == input$modalidad_prensa]
    etiqueta_anio <- names(opciones_anio)[opciones_anio == input$anio_prensa]

    layout_columns(
      col_widths = c(6, 6),
      div(
        style = "background: #232A35; padding: 8px 12px; border-radius: 8px;",
        span("Umbral vertical X̄ (", etiqueta_mod, " · ", etiqueta_anio, "): ",
             style = paste0("color:", gris_texto, "; font-size: 13px")),
        strong(paste0(formato(media_x, 1), " por 100.000 hab."),
               style = paste0("color:", ambar, "; font-size: 14px"))
      ),
      div(
        style = "background: #232A35; padding: 8px 12px; border-radius: 8px;",
        span("Umbral horizontal Ȳ (% noticias negativas · ", etiqueta_anio, "): ",
             style = paste0("color:", gris_texto, "; font-size: 13px")),
        strong(paste0(formato(media_y, 1), " %"),
               style = paste0("color:", azul, "; font-size: 14px"))
      )
    )
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

  # Clic en un polígono del mapa de clusters o en una tarjeta: ilumina ese grupo
  observeEvent(input$mapa_clusters_shape_click, {
    loc_clic <- input$mapa_clusters_shape_click$id
    req(loc_clic)
    grupo_clic <- datos_promedio_global$cluster_nombre[datos_promedio_global$localidad == loc_clic]
    if (length(grupo_clic) == 1) {
      nuevo_grupo <- ifelse(input$grupo_resaltado == grupo_clic, "Todos", grupo_clic)
      updateRadioButtons(session, "grupo_resaltado", selected = nuevo_grupo)
    }
  })

  observeEvent(input$clic_tarjeta_cluster, {
    grupo_clic <- input$clic_tarjeta_cluster
    req(grupo_clic)
    nuevo_grupo <- ifelse(input$grupo_resaltado == grupo_clic, "Todos", grupo_clic)
    updateRadioButtons(session, "grupo_resaltado", selected = nuevo_grupo)
  })

  output$mapa_clusters <- renderLeaflet({
    capa <- geo_localidades |>
      select(codigo_localidad, geometry) |>
      inner_join(datos_promedio_global, by = "codigo_localidad")

    crear_etiqueta_cluster <- function(df_sub) {
      lapply(seq_len(nrow(df_sub)), function(i) {
        s_val <- df_sub$silueta_localidad[i]
        nivel_s <- case_when(
          s_val >= 0.50 ~ "Cohesión alta con su grupo",
          s_val >= 0.25 ~ "Cohesión moderada",
          s_val >= 0.00 ~ "Zona de transición",
          TRUE          ~ "Perfil híbrido / frontera entre grupos"
        )
        HTML(paste0(
          "<div style='font-family: Archivo, sans-serif; color: #E9EDF2; line-height: 1.35;'>",
          "<strong style='font-size: 14px; color: ", colores_cluster_iluminado[df_sub$cluster_nombre[i]], ";'>",
          df_sub$localidad[i], "</strong><br>",
          "<span style='color: #9AA4B2; font-size: 12px;'>Clúster: </span>",
          "<strong>", df_sub$cluster_nombre[i], "</strong><br>",
          "<span style='color: #9AA4B2; font-size: 12px;'>Coeficiente de silueta (s<sub>i</sub>): </span>",
          "<strong style='color: ", ambar, "; font-size: 13.5px;'>", formato(s_val, 3), "</strong> ",
          "<span style='color: #9AA4B2; font-size: 11.5px;'>(", nivel_s, ")</span><br>",
          "<span style='color: #9AA4B2; font-size: 11.5px;'>Total: ", formato(df_sub$tasa_hurto_total[i], 0),
          " · Personas: ", formato(df_sub$tasa_hurto_personas[i], 0),
          " · Residencias: ", formato(df_sub$tasa_hurto_residencias[i], 1),
          " · Motos: ", formato(df_sub$tasa_hurto_motos[i], 1), "</span>",
          "</div>"
        ))
      })
    }

    opciones_label <- labelOptions(
      style = list(
        "background-color" = "#171B22",
        "border"           = "1px solid #F0A43A",
        "border-radius"    = "8px",
        "padding"          = "8px 10px",
        "box-shadow"       = "0 4px 14px rgba(0,0,0,0.65)"
      ),
      direction = "auto",
      opacity   = 0.96
    )

    mapa_base <- leaflet(capa) |>
      agregar_mapa_base()

    if (input$grupo_resaltado == "Todos") {
      mapa_base |>
        addPolygons(
          layerId          = ~localidad,
          fillColor        = unname(colores_cluster[capa$cluster_nombre]),
          fillOpacity      = 0.85,
          color            = "#1F2630",
          weight           = 1.8,
          label            = crear_etiqueta_cluster(capa),
          labelOptions     = opciones_label,
          highlightOptions = highlightOptions(
            weight       = 3.5,
            color        = "#FFFFFF",
            fillOpacity  = 0.98,
            bringToFront = TRUE
          )
        )
    } else {
      capa_otros <- capa |> filter(cluster_nombre != input$grupo_resaltado)
      capa_sel   <- capa |> filter(cluster_nombre == input$grupo_resaltado)
      color_ilu  <- unname(colores_cluster_iluminado[input$grupo_resaltado])

      mapa_base |>
        addPolygons(
          data             = capa_otros,
          layerId          = ~localidad,
          fillColor        = unname(colores_cluster[capa_otros$cluster_nombre]),
          fillOpacity      = 0.25,
          color            = "#2A303A",
          weight           = 1.2,
          label            = crear_etiqueta_cluster(capa_otros),
          labelOptions     = opciones_label,
          highlightOptions = highlightOptions(
            weight       = 2.5,
            color        = "#9AA4B2",
            fillOpacity  = 0.55,
            bringToFront = FALSE
          )
        ) |>
        addPolylines(
          data    = capa_sel,
          color   = color_ilu,
          weight  = 8,
          opacity = 0.45
        ) |>
        addPolygons(
          data             = capa_sel,
          layerId          = ~localidad,
          fillColor        = color_ilu,
          fillOpacity      = 0.96,
          color            = "#FFFFFF",
          weight           = 2.8,
          opacity          = 1.0,
          label            = crear_etiqueta_cluster(capa_sel),
          labelOptions     = opciones_label,
          highlightOptions = highlightOptions(
            weight       = 4.0,
            color        = ambar,
            fillOpacity  = 1.0,
            bringToFront = TRUE
          )
        )
    }
  })

  output$tarjetas_clusters <- renderUI({
    resumen <- datos_promedio_global |>
      group_by(cluster_nombre) |>
      summarise(
        n_localidades = n(),
        total         = mean(tasa_hurto_total),
        personas      = mean(tasa_hurto_personas),
        residencias   = mean(tasa_hurto_residencias),
        motos         = mean(tasa_hurto_motos),
        silueta_media = mean(silueta_localidad, na.rm = TRUE),
        miembros      = paste(sort(localidad), collapse = ", "),
        .groups = "drop"
      ) |>
      arrange(desc(total))

    tarjetas <- lapply(seq_len(nrow(resumen)), function(i) {
      g <- resumen[i, ]
      resaltada <- input$grupo_resaltado == g$cluster_nombre
      color_borde <- ifelse(resaltada, colores_cluster_iluminado[g$cluster_nombre], borde)
      sombra <- ifelse(
        resaltada,
        paste0("0 0 16px ", colores_cluster[g$cluster_nombre], "66"),
        "none"
      )

      div(
        onclick = sprintf("Shiny.setInputValue('clic_tarjeta_cluster', '%s', {priority: 'event'})", g$cluster_nombre),
        style   = "cursor: pointer;",
        card(
          style = paste0(
            "border: 2px solid ", color_borde, "; ",
            "box-shadow: ", sombra, "; ",
            "background: ", ifelse(resaltada, "#1E2530", tarjeta), "; ",
            "transition: all 0.2s ease;"
          ),
          card_header(
            span("● ", style = paste0("color:", ifelse(resaltada, colores_cluster_iluminado[g$cluster_nombre], colores_cluster[g$cluster_nombre]))),
            strong(g$cluster_nombre),
            span(
              paste0(
                ifelse(g$n_localidades == 1, "1 localidad", paste0(g$n_localidades, " localidades")),
                " · Silueta media: ", formato(g$silueta_media, 2)
              ),
              style = paste0("float: right; color:", ifelse(resaltada, "#E9EDF2", gris_texto), "; font-size: 12.5px")
            )
          ),
          layout_columns(
            col_widths = c(3, 3, 3, 3),
            div(p("Total", style = paste0("color:", gris_texto, "; margin: 0")),
                h4(formato(g$total), style = paste0("color:", ambar))),
            div(p("Personas", style = paste0("color:", gris_texto, "; margin: 0")),
                h4(formato(g$personas), style = paste0("color:", ambar))),
            div(p("Residencias", style = paste0("color:", gris_texto, "; margin: 0")),
                h4(formato(g$residencias, 1), style = paste0("color:", ambar))),
            div(p("Motos", style = paste0("color:", gris_texto, "; margin: 0")),
                h4(formato(g$motos, 1), style = paste0("color:", ambar)))
          ),
          p(g$miembros, style = paste0("color:", gris_texto, "; font-size: 13px; margin-bottom: 0"))
        )
      )
    })

    tagList(
      tarjetas,
      p("Tasas promedio del grupo, por 100.000 habitantes al año. Haz clic en una tarjeta, en el mapa o en el cubo 3D para iluminar el clúster.",
        style = paste0("color:", gris_texto, "; font-size: 12px"))
    )
  })

  # Clic en esfera o centroide del cubo 3D: alterna el resaltado del clúster
  observeEvent(event_data("plotly_click", source = "clusters_3d"), {
    clic <- event_data("plotly_click", source = "clusters_3d")
    req(!is.null(clic), !is.null(clic$customdata), length(clic$customdata) == 1)
    grupo_clic <- as.character(clic$customdata)
    if (grupo_clic %in% names(colores_cluster)) {
      nuevo_grupo <- ifelse(input$grupo_resaltado == grupo_clic, "Todos", grupo_clic)
      updateRadioButtons(session, "grupo_resaltado", selected = nuevo_grupo)
    }
  })

  output$grafico_clusters_3d <- renderPlotly({
    req(input$grupo_resaltado)
    usar_z      <- isTRUE(input$escala_z_3d)
    ver_nombres <- isTRUE(input$mostrar_nombres_3d)
    grupo_sel   <- input$grupo_resaltado
    datos_esc   <- datos_clusters_3d[[if (usar_z) "zscore" else "tasas"]]

    fig <- plot_ly(source = "clusters_3d")

    for (k in names(colores_cluster)) {
      es_activo <- (grupo_sel == "Todos" || grupo_sel == k)
      col_k     <- if (grupo_sel == k) unname(colores_cluster_iluminado[k]) else unname(colores_cluster[k])
      op_pts    <- if (es_activo) 0.94 else 0.16
      op_lin    <- if (es_activo) 0.48 else 0.08
      op_cen    <- if (es_activo) 1.00 else 0.18
      tam_pts   <- if (grupo_sel == k) 8.5 else 7
      tam_cen   <- if (grupo_sel == k) 12.5 else 10.5
      col_txt   <- if (es_activo) "#E9EDF2" else "rgba(154, 164, 178, 0.22)"

      sub_pts <- datos_esc$puntos[[k]]
      sub_seg <- datos_esc$segmentos[[k]]
      sub_cen <- datos_esc$centroides[[k]]

      args_pts <- list(
        p           = fig,
        x           = sub_pts$x,
        y           = sub_pts$y,
        z           = sub_pts$z,
        name        = k,
        legendgroup = k,
        showlegend  = TRUE,
        type        = "scatter3d",
        mode        = if (ver_nombres) "markers+text" else "markers",
        customdata  = sub_pts$cluster_nombre,
        hovertext   = sub_pts$tooltip_loc,
        hoverinfo   = "text",
        marker      = list(
          size    = tam_pts,
          color   = col_k,
          opacity = op_pts,
          line    = list(color = fondo, width = 1.2)
        )
      )
      if (ver_nombres) {
        args_pts$text         <- sub_pts$localidad
        args_pts$textposition <- "top center"
        args_pts$textfont     <- list(size = 10, color = col_txt, family = "Archivo")
      }

      fig <- do.call(add_trace, args_pts) |>
        add_trace(
          x           = sub_seg$x,
          y           = sub_seg$y,
          z           = sub_seg$z,
          name        = k,
          legendgroup = k,
          showlegend  = FALSE,
          type        = "scatter3d",
          mode        = "lines",
          line        = list(color = col_k, width = if (grupo_sel == k) 3 else 2),
          opacity     = op_lin,
          hoverinfo   = "none"
        ) |>
        add_trace(
          x           = I(sub_cen$x),
          y           = I(sub_cen$y),
          z           = I(sub_cen$z),
          name        = paste0("Centroide: ", k),
          legendgroup = k,
          showlegend  = FALSE,
          type        = "scatter3d",
          mode        = "markers",
          customdata  = I(sub_cen$cluster_nombre),
          hovertext   = I(sub_cen$tooltip_cen),
          hoverinfo   = "text",
          marker      = list(
            size    = tam_cen,
            symbol  = "diamond",
            color   = col_k,
            opacity = op_cen,
            line    = list(color = "#FFFFFF", width = 1.6)
          )
        )
    }

    tit_x <- if (usar_z) "Z-score: Hurto personas"    else "Hurto personas (tasa/100k)"
    tit_y <- if (usar_z) "Z-score: Hurto residencias" else "Hurto residencias (tasa/100k)"
    tit_z <- if (usar_z) "Z-score: Hurto motos"       else "Hurto motos (tasa/100k)"

    eje_oscuro <- function(titulo_eje) {
      list(
        title           = list(text = titulo_eje, font = list(size = 11.5, color = "#E9EDF2")),
        tickfont        = list(size = 9.5, color = gris_texto),
        showbackground  = TRUE,
        backgroundcolor = "#13171E",
        gridcolor       = borde,
        zerolinecolor   = "#3E4756"
      )
    }

    fig |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor  = "rgba(0,0,0,0)",
        font          = list(color = "#E9EDF2", family = "Archivo"),
        uirevision    = if (usar_z) "zscore" else "tasas",
        margin        = list(l = 10, r = 10, b = 35, t = 15),
        scene         = list(
          aspectmode = "cube",
          xaxis      = eje_oscuro(tit_x),
          yaxis      = eje_oscuro(tit_y),
          zaxis      = eje_oscuro(tit_z),
          camera     = list(eye = list(x = 1.45, y = -1.45, z = 0.75))
        ),
        legend = list(
          orientation = "h",
          x           = 0.5,
          xanchor     = "center",
          y           = -0.04,
          font        = list(color = "#E9EDF2", size = 12)
        )
      ) |>
      config(
        displayModeBar = "hover",
        displaylogo    = FALSE,
        modeBarButtonsToRemove = list("toImage", "sendDataToCloud")
      ) |>
      event_register("plotly_click")
  }) |>
    bindCache(input$grupo_resaltado, input$mostrar_nombres_3d, input$escala_z_3d)

  ## 6.5 Pestaña 5: Sentometrics y Elastic Net ----

  output$kpi_r2_modelo <- renderText({
    paste0(formato(metricas_modelo$r2_in_sample * 100, 1), " %")
  })

  output$kpi_hiper_modelo <- renderText({
    paste0("α = ", formato(metricas_modelo$alpha_optimo, 1),
           " · λ = ", formato(metricas_modelo$lambda_optimo, 1))
  })

  output$kpi_activos_modelo <- renderText({
    paste0(metricas_modelo$n_activos, " de ", metricas_modelo$n_predictores)
  })

  output$kpi_rmse_modelo <- renderText({
    paste0(formato(metricas_modelo$rmse, 1), " pts")
  })

  output$selector_features_sento <- renderUI({
    req(input$grupo_serie_sento)
    df_sub <- measures_long |>
      filter(grupo_feature == input$grupo_serie_sento) |>
      distinct(feature, feature_label) |>
      arrange(feature_label)

    opciones <- setNames(df_sub$feature, df_sub$feature_label)

    selectizeInput(
      "features_sento_sel",
      "2. Series a comparar",
      choices  = opciones,
      selected = opciones,
      multiple = TRUE,
      options  = list(plugins = list("remove_button"))
    )
  })

  output$grafico_series_sento <- renderPlotly({
    req(input$features_sento_sel, input$lexico_sento, input$tiempo_sento)

    df_plot <- measures_long |>
      filter(
        feature %in% input$features_sento_sel,
        lexicon == input$lexico_sento,
        time    == input$tiempo_sento
      ) |>
      mutate(date = as.Date(date))

    req(nrow(df_plot) > 0)

    formas_picos <- list()
    if (isTRUE(input$ver_picos_sento)) {
      y_min <- min(df_plot$valor, na.rm = TRUE)
      y_max <- max(df_plot$valor, na.rm = TRUE)
      formas_picos <- lapply(peakdates_neg, function(f_pico) {
        list(
          type = "line",
          x0 = f_pico, x1 = f_pico,
          y0 = y_min,  y1 = y_max,
          line = list(color = "#E86A50", dash = "dot", width = 1.2)
        )
      })
    }

    plot_ly(
      df_plot,
      x     = ~date,
      y     = ~valor,
      color = ~feature_label,
      colors = c("#B08CF0", "#E86A50", "#3FB8A6", ambar, azul, "#F2C14E", "#8AC926"),
      type  = "scatter",
      mode  = "lines",
      line  = list(width = 2.4),
      hovertemplate = "<b>%{fullData.name}</b><br>Mes: %{x|%Y-%m}<br>Sentimiento: %{y:+.4f}<extra></extra>"
    ) |>
      layout(shapes = formas_picos) |>
      estilo_plotly("Mes (ventana móvil de 6 meses)", "Índice de sentimiento ponderado")
  })

  output$grafico_atribuciones_sento <- renderPlotly({
    req(input$dim_attr_sento, input$escala_attr_sento)

    df_base <- if (input$escala_attr_sento == "norm") attr_long_norm else attr_long_raw

    if (input$dim_attr_sento == "clusters") {
      df_dim <- df_base |>
        filter(dimension == "features", str_starts(componente, "c_"))
    } else if (input$dim_attr_sento == "temas") {
      df_dim <- df_base |>
        filter(dimension == "features", str_starts(componente, "tema_"))
    } else {
      df_dim <- df_base |>
        filter(dimension == input$dim_attr_sento)
    }

    df_dim <- df_dim |> mutate(date = as.Date(date))
    req(nrow(df_dim) > 0)

    titulo_eje_y <- if (input$escala_attr_sento == "norm") {
      "Atribución normalizada [-1, 1]"
    } else {
      "Aporte a la tasa mensual"
    }

    plot_ly(
      df_dim,
      x     = ~date,
      y     = ~atribucion,
      color = ~componente_label,
      colors = c("#B08CF0", "#E86A50", "#3FB8A6", ambar, azul, "#9AA4B2", "#F2C14E"),
      type  = "bar",
      hovertemplate = "<b>%{fullData.name}</b><br>Mes: %{x|%Y-%m}<br>Atribución: %{y:+.3f}<extra></extra>"
    ) |>
      layout(barmode = "relative") |>
      estilo_plotly("Mes de pronóstico", titulo_eje_y)
  })

  output$grafico_ajuste_sento <- renderPlotly({
    df_aj <- ajuste_temporal |>
      mutate(date = as.Date(date))

    plot_ly(df_aj, x = ~date) |>
      add_lines(
        y    = ~observado,
        name = "Observada (denuncias)",
        line = list(color = ambar, width = 2.6)
      ) |>
      add_lines(
        y    = ~predicho,
        name = "Predicha (Elastic Net)",
        line = list(color = azul, width = 2.4, dash = "dash")
      ) |>
      estilo_plotly("", "Tasa mensual / 100k hab.")
  })

  output$grafico_coefs_sento <- renderPlotly({
    top_coefs <- coeficientes_df |>
      slice_max(abs(coeficiente), n = 10, with_ties = FALSE) |>
      arrange(abs(coeficiente)) |>
      mutate(color_barra = ifelse(coeficiente >= 0, ambar, azul))

    plot_ly(
      top_coefs,
      x      = ~coeficiente,
      y      = ~variable,
      type   = "bar",
      orientation = "h",
      marker = list(color = ~color_barra),
      hovertemplate = "<b>%{y}</b><br>Coeficiente β: %{x:+.3f}<extra></extra>"
    ) |>
      layout(
        yaxis = list(
          categoryorder = "array",
          categoryarray = top_coefs$variable,
          tickfont      = list(size = 10)
        )
      ) |>
      estilo_plotly("Coeficiente β (Elastic Net)", "")
  })

  ## 6.6 Pestaña 6: Datos y método ----

  output$tabla_contrato_rds <- renderDT({
    tam_bundle <- formato(round(file.info(ruta_bundle)$size / (1024^2), 2), 2)
    contrato_df <- tibble::tribble(
      ~Artefacto, ~Objeto_Interno, ~Clase_S3, ~Contenido,
      "sentometrics_pipeline.rds", "corpus_sento",      "sento_corpus",     "993 noticias de las 3 modalidades objetivo con 6 features binarias (3 clústeres + 3 modalidades).",
      "sentometrics_pipeline.rds", "lexicons_es",       "sento_lexicons",   "Diccionarios nrc_es y crimen_es + tabla de modificadores de valencia en español (t = 1..4).",
      "sentometrics_pipeline.rds", "sentiment_scores",  "sentiment",        "Puntajes por noticia (how = 'proportionalPol') y validación de sensibilidad frente a TF-IDF.",
      "sentometrics_pipeline.rds", "peak_docs",         "list/data.table",  "Noticias extremas extraídas con peakdocs() sobre las 993 noticias objetivo.",
      "sentometrics_pipeline.rds", "sento_measures",    "sento_measures",   "36 series mensuales (6 features × 2 léxicos × 3 curvas temporales, lag = 6 meses).",
      "sentometrics_pipeline.rds", "measures_long",     "list (long/wide)", "1.872 observaciones mensuales (52 meses × 36 series) auditadas con measures_fill().",
      "sentometrics_pipeline.rds", "global_index",      "list/data.table",  "Índice distrital agregado (do.global = TRUE) y 8 fechas pico con peakdates().",
      "sentometrics_pipeline.rds", "attributions",      "sento_model",      "Modelo Elastic Net (BIC, h = 1) contra la tasa mensual real SIEDCO y atribuciones marginales.",
      "datos_consolidados_shiny.rds", "bundle_shiny",   "list",             paste0("Único paquete liviano (", tam_bundle, " MB) que carga app/app.R con paneles, geometrías, series y resultados.")
    )

    datatable(
      contrato_df,
      rownames = FALSE,
      colnames = c("Archivo .rds", "Componente", "Clase S3", "Descripción"),
      options  = list(dom = "t", pageLength = 10, scrollX = TRUE)
    )
  })
}

# 7. Ejecución de la App ----
shinyApp(ui = ui, server = server)
