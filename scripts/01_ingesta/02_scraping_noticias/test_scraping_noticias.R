# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediatico en Bogota (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/test_scraping_noticias.R
# ROL: Control de consistencia e integridad del corpus consolidado de noticias
# AUTORES: Juan Jose Echeverry, Miguelangel Palma, Sergio Lopez (Grupo 10)
# PROGRAMA: Maestria en Economia Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(stringr)

conflict_prefer("filter", "dplyr")
conflict_prefer("select", "dplyr")

# Carga del entorno del pipeline
source(here("scripts", "01_ingesta", "02_scraping_noticias", "scraping_google_news.R"))

# 1. Validacion de la matriz de consultas
q_kennedy    <- df_consultas |> filter(localidad == "Kennedy") |> pull(cadena_busqueda)
q_santafe    <- df_consultas |> filter(localidad == "Santa Fe") |> pull(cadena_busqueda)
q_candelaria <- df_consultas |> filter(localidad == "La Candelaria") |> pull(cadena_busqueda)

stopifnot(str_detect(q_kennedy, "hurto"))
stopifnot(str_detect(q_kennedy, '"Kennedy"'))
stopifnot(str_detect(q_santafe, "-futbol"))
stopifnot(str_detect(q_santafe, "-campin"))
stopifnot(!str_detect(q_kennedy, "localidad"))
stopifnot(!str_detect(q_candelaria, "localidad"))

# 2. Validacion de endpoints de sindicacion RSS
url_muestra <- df_consultas$url_rss[1]
stopifnot(str_detect(url_muestra, "news\\.google\\.com/rss/search"))
stopifnot(str_detect(url_muestra, "q="))
stopifnot(str_detect(url_muestra, "hl=es-419"))
stopifnot(str_detect(url_muestra, "gl=CO"))

# 3. Validacion de desinfeccion de cadenas de enlace
url_prueba <- "https://www.eltiempo.com/bogota/hurto-123?utm_source=twitter&utm_campaign=bogota"
url_limpia <- sub("\\?(utm_|ref_|fbclid).*", "", url_prueba)
stopifnot(url_limpia == "https://www.eltiempo.com/bogota/hurto-123")

# 4. Integridad del archivo consolidado
archivo_parquet <- here("data", "raw", "noticias_google_news_consolidado.parquet")
stopifnot(file.exists(archivo_parquet))

df_verif <- read_parquet(archivo_parquet)
stopifnot(nrow(df_verif) >= 2487)
stopifnot(sum(is.na(df_verif$enlace)) == 0)
stopifnot(sum(is.na(df_verif$titulo)) == 0)
stopifnot(sum(is.na(df_verif$cuerpo)) == 0)
stopifnot(length(unique(df_verif$localidad)) >= 19)
stopifnot(max(as.Date(df_verif$fecha_chunk_desde), na.rm = TRUE) <= as.Date("2026-09-30"))
stopifnot(min(as.Date(df_verif$fecha_chunk_desde), na.rm = TRUE) >= as.Date("2022-01-01"))

# 5. Validacion de tipificacion de medios
stopifnot("tipo_medio" %in% names(df_verif))
stopifnot(sum(is.na(df_verif$tipo_medio)) == 0)
stopifnot("Institucional" %in% unique(df_verif$tipo_medio))

# 6. Validacion de confianza geografica
stopifnot("confianza_geografica" %in% names(df_verif))
stopifnot(all(df_verif$confianza_geografica %in% c("Alta", "Media")))

# 7. Validacion de Nomenclatura Oficial de Delitos de Alto Impacto (SCJ / SIEDCO)
stopifnot("delito_alto_impacto" %in% names(df_verif))
stopifnot("es_delito_alto_impacto" %in% names(df_verif))
stopifnot(sum(is.na(df_verif$delito_alto_impacto)) == 0)
stopifnot(sum(is.na(df_verif$es_delito_alto_impacto)) == 0)
stopifnot("Homicidio" %in% unique(df_verif$delito_alto_impacto))
stopifnot("Hurto a comercio" %in% unique(df_verif$delito_alto_impacto))
stopifnot("Hurto a personas" %in% unique(df_verif$delito_alto_impacto))
stopifnot("Hurto de automotores y autopartes" %in% unique(df_verif$delito_alto_impacto))
stopifnot("Hurto de celulares" %in% unique(df_verif$delito_alto_impacto))
stopifnot("Extorsion" %in% unique(df_verif$delito_alto_impacto))

# Dummies individuales por delito de alto impacto
stopifnot(c("delito_homicidio", "delito_hurto_personas", "delito_hurto_comercio", 
            "delito_hurto_celulares", "delito_extorsion") %in% names(df_verif))

# 8. Estructura temporal de panel
stopifnot(c("año", "mes", "año_mes", "trimestre", "semana_año") %in% names(df_verif))
stopifnot(sum(is.na(df_verif$año_mes)) == 0)
stopifnot(all(str_detect(df_verif$año_mes, "^202[2-6]-(0[1-9]|1[0-2])$")))

# Resumen de verificacion exitosa
print(data.frame(
  control = c(
    "consultas_booleanas", 
    "endpoints_rss", 
    "limpieza_urls", 
    "integridad_parquet", 
    "rango_temporal",
    "tipificacion_medios",
    "confianza_geografica",
    "delitos_alto_impacto_siedco",
    "variables_panel_tiempo"
  ),
  estado  = rep("CONFORME", 9)
), row.names = FALSE)
