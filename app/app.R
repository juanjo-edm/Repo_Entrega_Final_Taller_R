# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ROL: Aplicación Interactiva Shiny (Dashboard Territorial y Sentimiento)
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Librerías requeridas ----
library(shiny)
library(bslib)
library(here)
library(dplyr)
library(ggplot2)
library(DT)
library(leaflet)

## 1.2 Rutas y Carga de Insumos Procesados ----
ruta_datos_clean <- here::here("data", "processed")
archivo_shiny    <- file.path(ruta_datos_clean, "datos_consolidados_shiny.rds")

# 2. Interfaz de Usuario (UI) ----
# Requerimiento enunciado final: mapa de hurtos, series de sentimiento sentometrics,
# perfiles K-means, filtros por localidad/año y tabla de noticias.

ui <- page_sidebar(
  theme = bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = "#1f77b4"
  ),
  title = "Hurtos y Sentimiento Mediático en Bogotá (2022–2026)",
  
  sidebar = sidebar(
    title = "Controles y Filtros"
    # [Placeholder] Controles de selección de localidad, año y tipo de hurto
  ),
  
  # [Placeholder] Paneles de visualización: Mapa interactivo, series de sentimiento y tabla
  card(
    card_header("Tablero en desarrollo"),
    p("La aplicación consumirá los datos consolidados generados por el pipeline.")
  )
)

# 3. Lógica del Servidor (Server) ----

server <- function(input, output, session) {
  # [Placeholder] Reactivos y renderizadores para mapas, gráficos y tablas DT
}

# 4. Ejecución de la Aplicación ----
shinyApp(ui = ui, server = server)
