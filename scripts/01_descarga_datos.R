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
ruta_ingesta_abiertos <- here::here("scripts", "01_ingesta", "01_datos_abiertos")
ruta_ingesta_scraping <- here::here("scripts", "01_ingesta", "02_scraping_noticias")
ruta_raw              <- here::here("data", "raw")

# 2. Ingesta de Datos Abiertos de Bogotá (API Socrata / SoQL) ----
message("\n>>> [1/2] Iniciando ingesta de Datos Abiertos (Delitos, Población, Mapas)...")
source(file.path(ruta_ingesta_abiertos, "datos_abiertos_bogota.R"), echo = FALSE)

# 3. Consolidación e Ingesta de Noticias de Google News ----
if (!file.exists(file.path(ruta_raw, "noticias", "noticias_google_news_consolidado.parquet"))) {
  message("\n>>> [2/3] Consolidando subtablas históricas de noticias...")
  source(file.path(ruta_ingesta_scraping, "00_consolidar_subtablas_historicas.R"), echo = FALSE)
} else {
  message("\n>>> [2/3] Base de noticias consolidada verificada en data/raw/noticias_google_news_consolidado.parquet.")
}

message("\n>>> [3/3] Para ejecutar scraping incremental de meses adicionales con RSelenium:")
message("    source(here::here('scripts', '01_ingesta', '02_scraping_noticias', 'scraping_google_news.R'))")
message("    ejecutar_scraping_localidades()")

message("\n✔ Orquestador de Módulo 01 ejecutado con éxito.")
