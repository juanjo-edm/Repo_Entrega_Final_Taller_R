# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Módulo 01 - Orquestador de Ingesta (Datos Abiertos y Scraping Google News)
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
rm(list = ls())
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----
library(here)
library(conflicted)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas con {here} ----
ruta_ingesta <- here::here("scripts", "01_ingesta")
ruta_raw     <- here::here("data", "raw")

# 2. Ingesta de Datos Abiertos de Bogotá (API Socrata / SoQL) ----
message("\n>>> [1/2] Iniciando ingesta de Datos Abiertos (Delitos, Población, Mapas)...")
source(file.path(ruta_ingesta, "datos_abiertos_bogota.R"), echo = FALSE)

# 3. Web Scraping de Google News (SERP + Checkpointing) ----
message("\n>>> [2/2] Módulo de Scraping de Noticias preparado.")
message("    Para iniciar la recolección con RSelenium ejecute:")
message("    source(here::here('scripts', '01_ingesta', 'scraping_google_news.R'))")
message("    ejecutar_scraping_localidades()")
message("    consolidar_noticias_scraping()")

message("\n✔ Orquestador de Módulo 01 ejecutado con éxito.")
