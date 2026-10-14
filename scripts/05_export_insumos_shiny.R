# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Módulo 05 - Consolidación y Exportación de Insumos para la Shiny App
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
rm(list = ls())
options(scipen = 999)
set.seed(20261014)

## 1.2 Instalación y carga de librerías ----
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(sf)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_clean <- here::here("data", "processed")
ruta_app_data    <- here::here("app")

# 2. Cruce de Bases Procesadas ----
# Integración de tasas de delito, sentimiento de prensa y clústeres por Localidad x Año

# 3. Integración con Cartografía Vectorial (Shapefile / GeoJSON) ----
# Geometrías oficiales de las 19 localidades urbanas

# 4. Exportación de Insumos para Shiny ----
# Guardado del dataset consolidado listo para lectura en la aplicación
