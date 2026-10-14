# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Web Scraping Robusto de Noticias en Google News con Checkpointing
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
  "here", "conflicted", "RSelenium", "netstat", "arrow", "readr",
  "dplyr", "tidyr", "stringr", "glue", "lubridate", "rvest", "httr"
)

for (pkg in librerias_requeridas) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

library(here)
library(conflicted)
library(RSelenium)
library(netstat)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(glue)
library(lubridate)
library(rvest)
library(httr)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas con {here} ----
ruta_datos_raw      <- here::here("data", "raw")
ruta_noticias_raw   <- here::here("data", "raw", "noticias")
ruta_salida_tablas  <- here::here("output", "tables")

if (!dir.exists(ruta_noticias_raw)) dir.create(ruta_noticias_raw, recursive = TRUE)

# 2. Configuración de Parámetros y Consultas Booleanas ----

## 2.1 Catálogo de las 19 localidades urbanas ----
localidades <- c(
  "USAQUÉN", "CHAPINERO", "SANTA FE", "SAN CRISTÓBAL", "USME",
  "TUNJUELITO", "BOSA", "KENNEDY", "FONTIBÓN", "ENGATIVÁ",
  "SUBA", "BARRIOS UNIDOS", "TEUSAQUILLO", "LOS MÁRTIRES",
  "ANTONIO NARIÑO", "PUENTE ARANDA", "LA CANDELARIA", 
  "RAFAEL URIBE URIBE", "CIUDAD BOLÍVAR"
)

## 2.2 Función para forzar AND Booleano estricto (+) en Google ----
palabras_obligatorias <- function(texto) {
  palabras <- strsplit(texto, " ")[[1]]
  paste0("+", palabras, collapse = " ")
}

## 2.3 Rango temporal mensual (2022 a 2025) ----
fecha_inicio <- as.Date("2022-01-01")
fecha_fin    <- as.Date("2025-12-31")

inicios_mes <- seq(from = floor_date(fecha_inicio, "month"),
                   to   = floor_date(fecha_fin, "month"),
                   by   = "1 month")
fines_mes   <- pmin(inicios_mes %m+% months(1) - days(1), fecha_fin)

## 2.4 Parámetros de navegación y scraping ----
hl                  <- "es-419" # Español Latinoamérica
gl                  <- "CO"     # Colombia
max_paginas_por_mes <- 15       # Hasta 150 resultados por mes/localidad
espera_min          <- 2.0
espera_max          <- 4.0

formatear_mmddyyyy <- function(fecha) format(as.Date(fecha), "%m/%d/%Y")

build_google_news_url <- function(query, dmin, dmax, start = 0, hl = "es-419", gl = "CO") {
  q      <- utils::URLencode(query, reserved = TRUE)
  cd_min <- formatear_mmddyyyy(dmin)
  cd_max <- formatear_mmddyyyy(dmax)
  glue::glue(
    "https://www.google.com/search?q={q}",
    "&tbm=nws&hl={hl}&gl={gl}",
    "&tbs=cdr:1,cd_min:{cd_min},cd_max:{cd_max}",
    "&start={start}"
  )
}

# 3. Funciones de Extracción y Resiliencia en Navegador ----

## 3.1 Gestión de consentimiento de cookies ----
aceptar_consentimiento <- function(remDr) {
  try({
    Sys.sleep(runif(1, espera_min, espera_max))
    btns <- remDr$findElements(
      "css selector",
      "button#L2AGLb, button[aria-label*='Acepto'], button[aria-label*='Estoy de acuerdo']"
    )
    if (length(btns) > 0) {
      btns[[1]]$clickElement()
      Sys.sleep(runif(1, 1.0, 2.0))
    }
  }, silent = TRUE)
}

## 3.2 Selectores en cascada para atributos y textos ----
get_first_text <- function(node, css_vec) {
  for (css in css_vec) {
    kids <- try(node$findChildElements("css selector", css), silent = TRUE)
    if (!inherits(kids, "try-error") && length(kids) > 0) {
      val <- try(kids[[1]]$getElementText()[[1]], silent = TRUE)
      if (!inherits(val, "try-error") && !is.null(val) && nchar(val) > 0) return(val)
    }
  }
  NA_character_
}

get_first_attr <- function(node, css_vec, attr) {
  for (css in css_vec) {
    kids <- try(node$findChildElements("css selector", css), silent = TRUE)
    if (!inherits(kids, "try-error") && length(kids) > 0) {
      val <- try(kids[[1]]$getElementAttribute(attr)[[1]], silent = TRUE)
      if (!inherits(val, "try-error") && !is.null(val) && nchar(val) > 0) return(val)
    }
  }
  NA_character_
}

## 3.3 Extracción de página de resultados SERP ----
extraer_pagina_serp <- function(remDr, consulta, localidad, dmin, dmax, pagina_idx) {
  Sys.sleep(runif(1, espera_min, espera_max))
  contenedores <- remDr$findElements(
    "css selector",
    "div.SoaBEf, div.dbsr, div.Gx5Zad.fP1Qef.xpd.EtOod.pkphOe"
  )
  if (length(contenedores) == 0) return(tibble::tibble())
  
  rows <- lapply(contenedores, function(b) {
    titulo      <- get_first_text(b, c("div[role='heading']", "h3", "div.JheGif.nDgy9d"))
    enlace      <- get_first_attr(b, c("a.VDXfz", "a"), "href")
    fuente      <- get_first_text(b, c("div.SVJrMe a", "div.CEMjEf span", "span.xQ82C.e8fRJf", "span.wmnc8c"))
    fecha_texto <- get_first_text(b, c("time", "span.WG9SHc span", "span.OSrXXb"))
    fecha_iso   <- get_first_attr(b, c("time"), "datetime")
    resumen     <- get_first_text(b, c("div.GI74Re", "div.Y3v8qd", "div.gG0TJc"))
    
    tibble::tibble(
      localidad         = localidad,
      consulta          = consulta,
      titulo            = titulo,
      resumen           = resumen,
      fuente            = fuente,
      fecha_texto       = fecha_texto,
      fecha_iso         = fecha_iso,
      enlace            = enlace,
      fecha_chunk_desde = as.Date(dmin),
      fecha_chunk_hasta = as.Date(dmax),
      pagina            = pagina_idx
    )
  })
  
  dplyr::bind_rows(rows) |>
    dplyr::filter(!is.na(titulo) | !is.na(enlace)) |>
    dplyr::distinct()
}

## 3.4 Extracción de cuerpo con fallback a resumen ----
extraer_cuerpo_noticia <- function(url, resumen_fallback) {
  if (is.na(url) || url == "") return(resumen_fallback)
  
  tryCatch({
    resp <- httr::GET(
      url = url,
      httr::add_headers(
        "User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Accept-Language" = "es-CO,es;q=0.9"
      ),
      httr::timeout(5)
    )
    
    if (httr::status_code(resp) != 200) return(resumen_fallback)
    
    html_doc <- rvest::read_html(httr::content(resp, as = "text", encoding = "UTF-8"))
    cuerpo   <- html_doc |>
      rvest::html_elements("p") |>
      rvest::html_text(trim = TRUE) |>
      paste(collapse = " ")
    
    if (nchar(cuerpo) < 50) return(resumen_fallback)
    return(cuerpo)
  }, error = function(e) {
    return(resumen_fallback)
  })
}

# 4. Loop Principal de Scraping con Checkpointing Incremental ----

ejecutar_scraping_localidades <- function(headless = FALSE) {
  message(">>> Iniciando navegador con RSelenium...")
  
  extra_caps <- list(
    chromeOptions = list(
      args = c(
        "--disable-blink-features=AutomationControlled",
        "--disable-infobars",
        "--no-sandbox"
      )
    )
  )
  
  rD <- RSelenium::rsDriver(
    browser   = "chrome",
    chromever = NULL,
    port      = netstat::free_port(),
    verbose   = FALSE,
    check     = FALSE,
    phantomver = NULL,
    extraCapabilities = extra_caps
  )
  
  remDr <- rD$client
  on.exit({
    try(remDr$close(), silent = TRUE)
    try(rD$server$stop(), silent = TRUE)
  })
  
  for (loc in localidades) {
    consulta <- paste0("+seguridad +Bogotá +localidad +hurtos ", palabras_obligatorias(loc))
    message(paste0("\n=== Localidad en proceso: ", loc, " ==="))
    
    for (i_mes in seq_along(inicios_mes)) {
      dmin <- inicios_mes[i_mes]
      dmax <- fines_mes[i_mes]
      
      nombre_limpio <- tolower(gsub("[^a-zA-Z0-9]", "_", loc))
      archivo_chunk <- file.path(
        ruta_noticias_raw,
        paste0("chunk_", nombre_limpio, "_", format(dmin, "%Y_%m"), ".parquet")
      )
      
      # Control de checkpointing: si ya existe el archivo particionado, se omite
      if (file.exists(archivo_chunk)) {
        message(paste0("  [Checkpoint] Omitiendo ", loc, " | ", format(dmin, "%Y-%m"), " (ya procesado)."))
        next
      }
      
      datos_mes <- list()
      start     <- 0L
      
      for (i_pag in 1:max_paginas_por_mes) {
        url <- build_google_news_url(consulta, dmin, dmax, start = start, hl = hl, gl = gl)
        remDr$navigate(url)
        aceptar_consentimiento(remDr)
        
        # Detección de CAPTCHA
        page_html <- try(remDr$getPageSource()[[1]], silent = TRUE)
        if (!inherits(page_html, "try-error") && str_detect(page_html, regex("unusual traffic|recaptcha", ignore_case = TRUE))) {
          warning("🚨 CAPTCHA detectado. Resuelve el desafío manualmente en el navegador.")
          Sys.sleep(30)
          remDr$navigate(url)
          aceptar_consentimiento(remDr)
        }
        
        df_pag <- extraer_pagina_serp(remDr, consulta, loc, dmin, dmax, pagina_idx = i_pag)
        
        if (nrow(df_pag) == 0) {
          break
        } else {
          datos_mes[[length(datos_mes) + 1]] <- df_pag
          start <- start + 10L
        }
      }
      
      if (length(datos_mes) > 0) {
        chunk_df <- dplyr::bind_rows(datos_mes) |>
          dplyr::distinct(enlace, .keep_all = TRUE)
        
        # Fase 2: Extracción de cuerpo con fallback
        chunk_df$cuerpo <- purrr::map2_chr(chunk_df$enlace, chunk_df$resumen, extraer_cuerpo_noticia)
        
        # Guardado del checkpoint de este mes
        arrow::write_parquet(chunk_df, archivo_chunk)
        message(paste0("  ✔ Guardado chunk: ", basename(archivo_chunk), " (", nrow(chunk_df), " noticias)"))
      } else {
        # Guardar tibble vacío para marcar el mes como completado sin noticias
        vacio_df <- tibble::tibble(
          localidad = loc, consulta = consulta, titulo = character(0),
          resumen = character(0), fuente = character(0), fecha_texto = character(0),
          fecha_iso = character(0), enlace = character(0), fecha_chunk_desde = as.Date(character(0)),
          fecha_chunk_hasta = as.Date(character(0)), pagina = integer(0), cuerpo = character(0)
        )
        arrow::write_parquet(vacio_df, archivo_chunk)
      }
    }
  }
  message("\n✔ Proceso de scraping finalizado.")
}

# 5. Consolidación y Validación Territorial ----

consolidar_noticias_scraping <- function() {
  archivos_chunks <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)
  if (length(archivos_chunks) == 0) {
    message("ℹ No hay chunks generados aún en data/raw/noticias/.")
    return(NULL)
  }
  
  message(paste0(">>> Consolidando ", length(archivos_chunks), " archivos particionados..."))
  noticias_total <- purrr::map_dfr(archivos_chunks, arrow::read_parquet) |>
    dplyr::filter(!is.na(titulo) & titulo != "") |>
    dplyr::distinct(enlace, .keep_all = TRUE)
  
  # Validación territorial: confirma que la localidad aparezca en el texto
  noticias_validadas <- noticias_total |>
    dplyr::filter(
      stringr::str_detect(titulo, stringr::regex(localidad, ignore_case = TRUE)) |
      stringr::str_detect(resumen, stringr::regex(localidad, ignore_case = TRUE)) |
      stringr::str_detect(cuerpo, stringr::regex(localidad, ignore_case = TRUE))
    )
  
  archivo_consolidado <- file.path(ruta_datos_raw, "noticias_google_news_consolidado.parquet")
  arrow::write_parquet(noticias_validadas, archivo_consolidado)
  
  message(paste0("✔ Base consolidada guardada en: ", archivo_consolidado))
  message(paste0("  Total noticias únicas validadas: ", format(nrow(noticias_validadas), big.mark = ",")))
  return(noticias_validadas)
}

# 6. Modo de Ejecución Directo ----
if (!interactive()) {
  # Si se ejecuta desde terminal con Rscript
  message("Para ejecutar el scraping interactivo, llame a ejecutar_scraping_localidades()")
}
