# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/scraping_google_news.R
# ROL: Pipeline Generalizable de Noticias en Google News (Motor RSS y Checkpointing)
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# DESCRIPCIÓN GENERAL:
# Este módulo implementa un pipeline 100% generalizable y parametrizable para
# la ingesta, limpieza, consolidación y auditoría de noticias sobre criminalidad
# en las 19 localidades urbanas de Bogotá D.C. mediante el motor oficial Google News RSS.
#
# CARACTERÍSTICAS DE GENERALIZACIÓN:
# 1. Rango Temporal Parametrizable (por defecto 2022-01-01 a 2026-09-30):
#    Permite recortar o expandir la ventana de análisis a cualquier rango de fechas.
# 2. Selección Flexible de Territorios:
#    Permite procesar las 19 localidades completas o subconjuntos específicos.
# 3. Consultas Booleanas y Filtro Deportivo:
#    Agrupación de sinónimos de delitos y exclusión de fútbol para Santa Fe.
# 4. Trazabilidad Atómica:
#    Guarda chunks particionados en Parquet, unifica con la serie histórica validada,
#    deduplica por URL limpia y título, y actualiza los metadatos de cobertura JSON.
#
# GUÍA RÁPIDA DE USO:
#   source(here::here("scripts", "01_ingesta", "02_scraping_noticias", "scraping_google_news.R"))
#   ejecutar_pipeline_noticias_completo(
#     fecha_inicio = "2022-01-01",
#     fecha_fin    = "2026-09-30"
#   )
# ==============================================================================

# 1. Configuración de Entorno y Dependencias ----

## 1.1 Opciones globales y reproducibilidad ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Verificación e instalación de paquetes requeridos ----
librerias_requeridas <- c(
  "here", "conflicted", "arrow", "readr", "dplyr", "tidyr",
  "stringr", "stringi", "glue", "lubridate", "xml2", "rvest",
  "httr", "purrr", "jsonlite"
)

for (pkg in librerias_requeridas) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(paste0("Instalando paquete faltante: ", pkg))
    install.packages(pkg)
  }
}

suppressPackageStartupMessages({
  library(here)        # Rutas relativas seguras
  library(conflicted)  # Resolución estricta de colisiones
  library(arrow)       # Lectura/escritura columnar Parquet
  library(readr)       # Lectura y exportación rápida
  library(dplyr)       # Transformación de datos
  library(tidyr)       # Tidy data
  library(stringr)     # Expresiones regulares
  library(stringi)     # Normalización de texto y remoción de acentos
  library(glue)        # Interpolación de cadenas
  library(lubridate)   # Manejo de fechas y parseo de marcas temporales
  library(xml2)        # Parseo de XML para el feed RSS
  library(rvest)       # Extracción de contenido web HTML
  library(httr)        # Peticiones HTTP seguras con timeout y headers
  library(purrr)       # Mapeo funcional
  library(jsonlite)    # Gestión de metadatos en JSON
})

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas del proyecto con {here} ----
ruta_datos_raw      <- here::here("data", "raw")
ruta_noticias_raw   <- here::here("data", "raw", "noticias")
ruta_salida_tablas  <- here::here("output", "tables")
archivo_cobertura   <- here::here("data", "raw", "noticias", "cobertura_historica.json")
archivo_consolidado <- here::here("data", "raw", "noticias_google_news_consolidado.parquet")
archivo_consol_rds  <- here::here("data", "raw", "noticias_google_news_consolidado.rds")

if (!dir.exists(ruta_noticias_raw)) {
  dir.create(ruta_noticias_raw, recursive = TRUE)
}

# 2. Catálogo Territorial y Consultas Booleanas ----

## 2.1 Las 19 localidades urbanas de Bogotá ----
localidades <- c(
  "USAQUÉN", "CHAPINERO", "SANTA FE", "SAN CRISTÓBAL", "USME",
  "TUNJUELITO", "BOSA", "KENNEDY", "FONTIBÓN", "ENGATIVÁ",
  "SUBA", "BARRIOS UNIDOS", "TEUSAQUILLO", "LOS MÁRTIRES",
  "ANTONIO NARIÑO", "PUENTE ARANDA", "LA CANDELARIA", 
  "RAFAEL URIBE URIBE", "CIUDAD BOLÍVAR"
)

## 2.2 Constructor de consultas para Google News RSS ----
#' Construye la consulta booleana optimizada para Google News RSS
#'
#' @param localidad Nombre de la localidad en texto plano.
#' @return Cadena de texto con la consulta lista para enviar al feed.
construir_consulta_rss <- function(localidad) {
  delitos_kw <- '(hurto OR robo OR atraco OR asalto OR inseguridad)'
  loc_nombre <- stringr::str_to_title(tolower(localidad))
  
  # Exclusión de noticias deportivas para Santa Fe
  if (tolower(loc_nombre) == "santa fe") {
    return(glue::glue('{delitos_kw} Bogota "{loc_nombre}" -futbol -liga -campin -dimayor -cardenal'))
  }
  
  glue::glue('{delitos_kw} Bogota "{loc_nombre}"')
}

# Alias para compatibilidad hacia atrás
construir_consulta_google <- construir_consulta_rss

#' Constructor de URL para Google News RSS
build_google_news_url <- function(query, dmin = NULL, dmax = NULL, start = 0, hl = "es-419", gl = "CO") {
  q <- utils::URLencode(query, reserved = TRUE)
  glue::glue("https://news.google.com/rss/search?q={q}&hl={hl}&gl={gl}&ceid={gl}:{hl}")
}

## 2.3 Limpieza y desinfección de URLs ----
#' Limpia URLs eliminando parámetros de analítica y rastreo
limpiar_enlace <- function(url) {
  if (is.na(url) || url == "") return(NA_character_)
  # Resolver posibles redirectores
  if (grepl("/url\\?q=", url)) {
    url <- sub("^.*/url\\?q=([^&]+).*$", "\\1", url)
    url <- utils::URLdecode(url)
  }
  # Remover parámetros UTM y de redes sociales
  sub("\\?(utm_|ref_|fbclid).*", "", url)
}

# 3. Funciones de Extracción del Motor RSS ----

#' Parsea una fecha en formato RFC 822 / GMT (estándar RSS)
parsear_fecha_rss <- function(fecha_str) {
  tryCatch({
    d <- as.Date(fecha_str, format = "%a, %d %b %Y")
    if (is.na(d)) {
      d <- as.Date(lubridate::parse_date_time(fecha_str, orders = c("dmy HMS", "ymd HMS", "a d b Y HMS z")))
    }
    if (is.na(d)) Sys.Date() else d
  }, error = function(e) {
    Sys.Date()
  })
}

#' Descarga el contenido editorial del artículo con fallback al resumen
extraer_cuerpo_noticia <- function(url, resumen_fallback) {
  if (is.na(url) || url == "") return(resumen_fallback)
  
  tryCatch({
    resp <- httr::GET(
      url = url,
      httr::add_headers(
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language" = "es-CO,es;q=0.9"
      ),
      httr::timeout(6)
    )
    
    if (httr::status_code(resp) != 200) return(resumen_fallback)
    
    html_doc <- rvest::read_html(httr::content(resp, as = "text", encoding = "UTF-8"))
    
    # Selectores semánticos de contenido principal
    nodos_articulo <- rvest::html_elements(
      html_doc,
      "article p, div.article-body p, div.story-contents p, div[itemprop='articleBody'] p"
    )
    
    if (length(nodos_articulo) == 0) {
      nodos_articulo <- rvest::html_elements(html_doc, "p")
    }
    
    cuerpo <- nodos_articulo |>
      rvest::html_text(trim = TRUE) |>
      paste(collapse = " ")
    
    if (nchar(cuerpo) < 50) return(resumen_fallback)
    return(cuerpo)
  }, error = function(e) {
    return(resumen_fallback)
  })
}

#' Consulta Google News RSS para una localidad y retorna un tibble estructurado
consultar_localidad_rss <- function(localidad, hl = "es-419", gl = "CO", descargar_cuerpos = FALSE) {
  query_str  <- construir_consulta_rss(localidad)
  query_enc  <- utils::URLencode(query_str, reserved = TRUE)
  url_rss    <- glue::glue("https://news.google.com/rss/search?q={query_enc}&hl={hl}&gl={gl}&ceid={gl}:{hl}")
  
  tryCatch({
    doc   <- xml2::read_xml(url_rss)
    items <- xml2::xml_find_all(doc, "//item")
    
    if (length(items) == 0) {
      return(tibble::tibble())
    }
    
    titulos    <- xml2::xml_text(xml2::xml_find_first(items, "title"))
    enlaces    <- xml2::xml_text(xml2::xml_find_first(items, "link"))
    fechas_raw <- xml2::xml_text(xml2::xml_find_first(items, "pubDate"))
    fuentes    <- xml2::xml_text(xml2::xml_find_first(items, "source"))
    desc_raw   <- xml2::xml_text(xml2::xml_find_first(items, "description"))
    
    # Limpiar resúmenes eliminando tags HTML
    resumenes <- purrr::map_chr(desc_raw, function(x) {
      if (is.na(x) || x == "") return(NA_character_)
      tryCatch(rvest::read_html(x) |> rvest::html_text(trim = TRUE), error = function(e) x)
    })
    
    # Parsear fechas exactas de publicación
    fechas_pub <- purrr::map_vec(fechas_raw, parsear_fecha_rss)
    
    df_loc <- tibble::tibble(
      localidad         = stringr::str_to_title(tolower(localidad)),
      consulta          = query_str,
      titulo            = titulos,
      resumen           = resumenes,
      fuente            = fuentes,
      fecha_texto       = fechas_raw,
      fecha_iso         = as.character(fechas_pub),
      enlace            = purrr::map_chr(enlaces, limpiar_enlace),
      fecha_chunk_desde = lubridate::floor_date(as.Date(fechas_pub), "month"),
      fecha_chunk_hasta = lubridate::ceiling_date(as.Date(fechas_pub), "month") - lubridate::days(1),
      pagina            = 1L
    ) |>
      dplyr::filter(!is.na(titulo) & titulo != "") |>
      dplyr::distinct(enlace, .keep_all = TRUE)
    
    if (descargar_cuerpos) {
      df_loc$cuerpo <- purrr::map2_chr(df_loc$enlace, df_loc$resumen, extraer_cuerpo_noticia)
    } else {
      df_loc$cuerpo <- df_loc$resumen
    }
    
    return(df_loc)
  }, error = function(e) {
    warning(paste0("Error consultando RSS para ", localidad, ": ", e$message))
    return(tibble::tibble())
  })
}

# 4. Orquestación del Scraping RSS por Localidad ----

#' Ejecuta la recolección automática por RSS para las localidades urbanas
ejecutar_scraping_rss <- function(localidades_objetivo = localidades, descargar_cuerpos = FALSE) {
  cat("\n==================================================================\n")
  cat("📡 INICIANDO RECOLECCIÓN DE NOTICIAS MEDIANTE GOOGLE NEWS RSS\n")
  cat(paste0("   Total de localidades a consultar: ", length(localidades_objetivo), "\n"))
  cat("==================================================================\n\n")
  
  total_articulos <- 0
  
  for (loc in localidades_objetivo) {
    nombre_slug <- tolower(stringi::stri_trans_general(loc, "Latin-ASCII"))
    nombre_slug <- gsub("[^a-z0-9]", "_", nombre_slug)
    archivo_chunk <- file.path(ruta_noticias_raw, paste0("chunk_rss_", nombre_slug, ".parquet"))
    
    message(paste0("🔄 Consultando RSS: ", loc, "..."))
    df_loc <- consultar_localidad_rss(loc, descargar_cuerpos = descargar_cuerpos)
    
    if (nrow(df_loc) > 0) {
      arrow::write_parquet(df_loc, archivo_chunk)
      total_articulos <- total_articulos + nrow(df_loc)
      message(paste0("  ✔ Guardado: ", basename(archivo_chunk), " (", nrow(df_loc), " noticias recuperadas)"))
    } else {
      message(paste0("  ℹ 0 noticias recuperadas para: ", loc))
    }
    
    Sys.sleep(1.5)
  }
  
  cat("\n==================================================================\n")
  cat(paste0("✔ Recolección RSS finalizada. Total noticias brutas descargadas: ", total_articulos, "\n"))
  cat("==================================================================\n\n")
}

# 5. Consolidación Generalizable y Filtrado Temporal ----

#' Consolida la base histórica con todos los chunks generados y aplica filtros temporales
#'
#' @param fecha_inicio Fecha mínima del corpus (por defecto 2022-01-01).
#' @param fecha_fin Fecha máxima del corpus (por defecto 2026-09-30).
#' @return Tibble invisible con el corpus unificado y delimitado.
consolidar_noticias_scraping <- function(fecha_inicio = as.Date("2022-01-01"),
                                         fecha_fin    = as.Date("2026-09-30")) {
  
  fecha_inicio <- as.Date(fecha_inicio)
  fecha_fin    <- as.Date(fecha_fin)
  
  message(paste0("\n>>> [Consolidación] Unificando y delimitando al rango generalizable:"))
  message(paste0("    Desde: ", fecha_inicio, " | Hasta: ", fecha_fin))
  
  # 1. Base histórica previa
  df_historico <- tibble::tibble()
  if (file.exists(archivo_consolidado)) {
    df_historico <- arrow::read_parquet(archivo_consolidado)
  }
  
  # 2. Leer chunks generados en data/raw/noticias/
  archivos_chunks <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)
  df_nuevos <- tibble::tibble()
  
  if (length(archivos_chunks) > 0) {
    df_nuevos <- purrr::map_dfr(archivos_chunks, function(f) {
      tryCatch(arrow::read_parquet(f), error = function(e) tibble::tibble())
    }) |>
      dplyr::filter(!is.na(titulo) & titulo != "")
  }
  
  # 3. Fusión total y deduplicación dual (URL limpia y título)
  noticias_total <- dplyr::bind_rows(df_historico, df_nuevos) |>
    dplyr::filter(!is.na(enlace) & enlace != "") |>
    dplyr::distinct(enlace, .keep_all = TRUE) |>
    dplyr::distinct(titulo, .keep_all = TRUE)
  
  # 4. Normalización de campos y delimitación temporal generalizable
  noticias_total <- noticias_total |>
    dplyr::mutate(
      fuente            = ifelse(is.na(fuente) | fuente == "", sub("^https?://([^/]+).*$", "\\1", enlace), fuente),
      fecha_chunk_desde = as.Date(fecha_chunk_desde)
    ) |>
    dplyr::filter(
      fecha_chunk_desde >= fecha_inicio & fecha_chunk_desde <= fecha_fin
    )
  
  # 5. Exportar base unificada en Parquet y RDS
  arrow::write_parquet(noticias_total, archivo_consolidado)
  saveRDS(noticias_total, archivo_consol_rds)
  
  message(paste0("  ✔ Base consolidada guardada en Parquet y RDS."))
  message(paste0("  ✔ Total noticias validadas en el rango (", fecha_inicio, " a ", fecha_fin, "): ", format(nrow(noticias_total), big.mark = ",")))
  
  # 6. Actualizar metadatos de cobertura temporal (cobertura_historica.json)
  try({
    cobertura <- noticias_total |>
      dplyr::group_by(localidad) |>
      dplyr::summarise(
        noticias_consolidadas = n(),
        fecha_min = min(as.Date(fecha_chunk_desde), na.rm = TRUE),
        fecha_max = max(as.Date(fecha_chunk_desde), na.rm = TRUE),
        meses_cubiertos = list(sort(unique(format(as.Date(fecha_chunk_desde), "%Y-%m")))),
        fuentes_principales = list(head(names(sort(table(fuente), decreasing = TRUE)), 5)),
        .groups = "drop"
      )
    
    metadatos <- list(
      proyecto = "Hurtos y Sentimiento Mediatico en Bogota (2022-2026)",
      fecha_actualizacion = as.character(Sys.time()),
      total_filas_consolidadas = nrow(noticias_total),
      rango_generalizable = list(
        inicio = as.character(min(as.Date(noticias_total$fecha_chunk_desde), na.rm = TRUE)),
        fin    = as.character(max(as.Date(noticias_total$fecha_chunk_desde), na.rm = TRUE))
      ),
      localidades = split(cobertura, seq_len(nrow(cobertura)))
    )
    
    jsonlite::write_json(metadatos, archivo_cobertura, pretty = TRUE, auto_unbox = TRUE)
    message(paste0("  ✔ Registro de cobertura actualizado en: ", archivo_cobertura))
  }, silent = TRUE)
  
  return(invisible(noticias_total))
}

#' Diagnóstico y auditoría completa del corpus consolidado
auditar_corpus_noticias <- function() {
  if (!file.exists(archivo_consolidado)) {
    message("⚠ No se encontró el archivo consolidado en data/raw/.")
    return(NULL)
  }
  
  df <- arrow::read_parquet(archivo_consolidado)
  
  cat("\n=======================================================\n")
  cat("📊 AUDITORÍA DEL CORPUS DE NOTICIAS (2022 A 2026-09)\n")
  cat("=======================================================\n")
  cat(paste0("Total de artículos: ", format(nrow(df), big.mark = ","), "\n"))
  cat(paste0("Rango temporal:     ", min(df$fecha_chunk_desde, na.rm=TRUE), " a ", max(df$fecha_chunk_desde, na.rm=TRUE), "\n"))
  cat(paste0("Medios únicos:      ", length(unique(df$fuente)), "\n\n"))
  
  cat("Distribución por año:\n")
  df_año <- df |>
    dplyr::mutate(año = lubridate::year(as.Date(fecha_chunk_desde))) |>
    dplyr::count(año)
  print(as.data.frame(df_año))
  
  cat("\nNoticias por localidad (Top 10):\n")
  df_loc <- df |> dplyr::count(localidad, sort = TRUE) |> head(10)
  print(as.data.frame(df_loc))
  
  cat("\nPrincipales medios de comunicación (Top 5):\n")
  df_fuente <- df |> dplyr::count(fuente, sort = TRUE) |> head(5)
  print(as.data.frame(df_fuente))
  
  cat("\nAuditoría de valores faltantes (NAs):\n")
  cat(paste0("  - Titular: ", sum(is.na(df$titulo)), "\n"))
  cat(paste0("  - Resumen: ", sum(is.na(df$resumen)), "\n"))
  cat(paste0("  - Enlace:  ", sum(is.na(df$enlace)), "\n"))
  cat(paste0("  - Cuerpo:  ", sum(is.na(df$cuerpo)), "\n"))
  cat("=======================================================\n\n")
  
  return(invisible(df))
}

# 6. Pipeline y Auto-Ejecución ----

#' Ejecuta el pipeline completo y generalizable de noticias de Google News
#'
#' @param fecha_inicio Fecha inicial del corpus (por defecto "2022-01-01").
#' @param fecha_fin Fecha final del corpus (por defecto "2026-09-30").
#' @param localidades_objetivo Localidades a incluir (por defecto las 19).
#' @param descargar_cuerpos Booleano para descargar cuerpo editorial.
#' @param ejecutar_descarga Booleano: TRUE ejecuta consulta RSS a Google, FALSE solo consolida/filtra.
#' @return Tibble invisible con el dataset delimitado.
ejecutar_pipeline_noticias_completo <- function(fecha_inicio = "2022-01-01",
                                                fecha_fin    = "2026-09-30",
                                                localidades_objetivo = localidades,
                                                descargar_cuerpos = FALSE,
                                                ejecutar_descarga = TRUE) {
  
  # 1. Recolección vía Google News RSS si se solicita
  if (isTRUE(ejecutar_descarga)) {
    ejecutar_scraping_rss(localidades_objetivo = localidades_objetivo, descargar_cuerpos = descargar_cuerpos)
  }
  
  # 2. Fusión, deduplicación y delimitación al rango solicitado
  df_final <- consolidar_noticias_scraping(fecha_inicio = fecha_inicio, fecha_fin = fecha_fin)
  
  # 3. Reporte diagnóstico
  auditar_corpus_noticias()
  
  return(invisible(df_final))
}

# Auto-ejecución inmediata por defecto al hacer source()
if (!exists("auto_ejecutar") || isTRUE(auto_ejecutar)) {
  ejecutar_pipeline_noticias_completo(
    fecha_inicio      = "2022-01-01",
    fecha_fin         = "2026-09-30",
    ejecutar_descarga = FALSE # Ya descargamos las noticias, aplica consolidación y delimitación inmediata
  )
}
