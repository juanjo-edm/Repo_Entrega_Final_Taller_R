# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Script Maestro Orquestador del Pipeline Completo
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
rm(list = ls())
options(scipen = 999)
set.seed(20261014)

## 1.2 Instalación y carga de librerías ----
librerias_requeridas <- c(
  "here", "conflicted", "arrow", "readr", "dplyr", "tidyr", 
  "ggplot2", "sentometrics", "sf", "xml2", "rvest"
)

for (pkg in librerias_requeridas) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(paste0("Instalando paquete faltante: ", pkg))
    install.packages(pkg)
  }
}

library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_scripts        <- here::here("scripts")
ruta_datos_raw      <- here::here("data", "raw")
ruta_datos_clean    <- here::here("data", "processed")
ruta_salida_tablas  <- here::here("output", "tables")
ruta_salida_figuras <- here::here("output", "figures")
ruta_app_data       <- here::here("app")

message(">>> Rutas del proyecto inicializadas correctamente.")

# 2. Ejecución Secuencial del Pipeline ----

## 2.1 Módulo 1: Ingesta de datos crudos por fuente ----
message("\n>>> [1a/5] Ingesta de Delitos SDSCJ...")
source(file.path(ruta_scripts, "01_ingesta", "01_delitos", "descarga_delitos_sdscj.R"), echo = FALSE)

message("\n>>> [1b/5] Ingesta de Población SDS...")
source(file.path(ruta_scripts, "01_ingesta", "02_poblacion", "descarga_poblacion_sds.R"), echo = FALSE)

message("\n>>> [1c/5] Ingesta de Prensa Google News...")
source(file.path(ruta_scripts, "01_ingesta", "03_noticias", "scraping_google_news.R"), echo = FALSE)

## 2.2 Módulo 2: Limpieza, homologación territorial y tasas ----
message("\n>>> [2/5] Ejecutando: 02_limpieza_indicadores.R...")
source(file.path(ruta_scripts, "02_limpieza_indicadores.R"), echo = FALSE)

## 2.3 Módulo 3: Análisis de sentimiento textual (sentometrics) ----
message("\n>>> [3/5] Ejecutando: 03_analisis_sentometrics.R...")
source(file.path(ruta_scripts, "03_analisis_sentometrics.R"), echo = FALSE)

## 2.3b Módulo 3b: Depuración del corpus según los 11 DAI de la SDSCJ ----
message("\n>>> [3b/5] Ejecutando: 02b_depuracion_noticias_dai.R...")
source(file.path(ruta_scripts, "02b_depuracion_noticias_dai.R"), echo = FALSE)

## 2.4 Módulo 4: Clustering territorial de criminalidad (K-means) ----
message("\n>>> [4/5] Ejecutando: 04_clustering_kmeans.R...")
source(file.path(ruta_scripts, "04_clustering_kmeans.R"), echo = FALSE)

## 2.5 Módulo 5: Consolidación y exportación para la Shiny App ----
message("\n>>> [5/5] Ejecutando: 05_export_insumos_shiny.R...")
source(file.path(ruta_scripts, "05_export_insumos_shiny.R"), echo = FALSE)

# 3. Auditoría y Verificación de Salidas ----

## 3.1 Comprobación programática de artefactos clave ----
archivos_esperados <- c(
  file.path(ruta_datos_clean, "hurtos", "panel_delitos_poblacion_localidad.parquet"),
  file.path(ruta_datos_clean, "hurtos", "panel_consolidado_localidad_anual.parquet"),
  file.path(ruta_datos_clean, "noticias", "noticias_procesadas.parquet"),
  file.path(ruta_datos_clean, "noticias", "noticias_con_sentimiento.parquet")
)

# Validación de existencia de insumos finales
for (archivo in archivos_esperados) {
  if (file.exists(archivo)) {
    message(paste0("✔ Artefacto verificado: ", basename(archivo)))
  } else {
    warning(paste0("⚠ Artefacto no encontrado: ", basename(archivo)))
  }
}

message("\n=== Pipeline completado con éxito. ===")
