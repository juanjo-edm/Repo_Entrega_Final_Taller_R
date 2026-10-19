# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ROL: Web Scraping Robusto de Noticias en Google News con RSelenium
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Instalación y carga de librerías ----
librerias_requeridas <- c(
  "here", "conflicted", "RSelenium", "netstat", "arrow", "readr",
  "dplyr", "tidyr", "stringr", "stringi", "glue", "lubridate", "rvest", "httr", "purrr", "jsonlite"
)

for (pkg in librerias_requeridas) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

suppressPackageStartupMessages({
  library(here)
  library(conflicted)
  library(RSelenium)
  library(netstat)
  library(arrow)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(stringi)
  library(glue)
  library(lubridate)
  library(rvest)
  library(httr)
  library(purrr)
  library(jsonlite)
})

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas con {here} ----
ruta_datos_raw      <- here::here("data", "raw")
ruta_noticias_raw   <- here::here("data", "raw", "noticias")
ruta_salida_tablas  <- here::here("output", "tables")
archivo_cobertura   <- here::here("data", "raw", "noticias", "cobertura_historica.json")
archivo_consolidado <- here::here("data", "raw", "noticias_google_news_consolidado.parquet")
archivo_consol_rds  <- here::here("data", "raw", "noticias_google_news_consolidado.rds")

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

## 2.2 Constructor de consultas optimizadas con comillas y sinónimos ----
construir_consulta_google <- function(localidad) {
  delitos_kw <- '("hurto" OR "hurtos" OR "robo" OR "robos" OR "atraco" OR "atracos" OR "inseguridad")'
  loc_nombre <- stringr::str_to_title(tolower(localidad))
  
  # Filtro negativo de exclusión para "Santa Fe" (evitar sesgo por el club de fútbol)
  if (tolower(loc_nombre) == "santa fe") {
    return(glue::glue('{delitos_kw} "Bogotá" "{loc_nombre}" -fútbol -liga -campín -dimayor -cardenal'))
  }
  
  glue::glue('{delitos_kw} "Bogotá" "{loc_nombre}"')
}

## 2.3 Rango temporal mensual (2022-01 a 2026-09) ----
fecha_inicio <- as.Date("2022-01-01")
fecha_fin    <- as.Date("2026-09-30")

inicios_mes <- seq(from = floor_date(fecha_inicio, "month"),
                   to   = floor_date(fecha_fin, "month"),
                   by   = "1 month")
fines_mes   <- pmin(inicios_mes %m+% months(1) - days(1), fecha_fin)

## 2.4 Parámetros de navegación y scraping ----
hl                  <- "es-419" # Español Latinoamérica
gl                  <- "CO"     # Colombia
max_paginas_por_mes <- 15       # Hasta 150 resultados por mes/localidad
espera_min          <- 3.0      # Pausas con jitter humano para evitar bloqueo
espera_max          <- 6.0

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
    Sys.sleep(runif(1, 1.5, 3.0))
    btns <- remDr$findElements(
      "css selector",
      "button#L2AGLb, button[aria-label*='Acepto'], button[aria-label*='Estoy de acuerdo'], button[aria-label*='Accept all']"
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

## 3.3 Limpieza de URL de seguimiento ----
limpiar_enlace <- function(url) {
  if (is.na(url) || url == "") return(NA_character_)
  # Si Google antepone su redirector (/url?q=...)
  if (grepl("/url\\?q=", url)) {
    url <- sub("^.*/url\\?q=([^&]+).*$", "\\1", url)
    url <- utils::URLdecode(url)
  }
  # Remover parámetros de analítica comunes
  sub("\\?(utm_|ref_|fbclid).*", "", url)
}

## 3.4 Extracción de página de resultados SERP ----
extraer_pagina_serp <- function(remDr, consulta, localidad, dmin, dmax, pagina_idx) {
  Sys.sleep(runif(1, espera_min, espera_max))
  contenedores <- remDr$findElements(
    "css selector",
    "div.SoaBEf, div.dbsr, div.Gx5Zad.fP1Qef.xpd.EtOod.pkphOe, div[jscontroller='d0NqJe']"
  )
  if (length(contenedores) == 0) return(tibble::tibble())
  
  rows <- lapply(contenedores, function(b) {
    titulo      <- get_first_text(b, c("div[role='heading']", "h3", "div.JheGif.nDgy9d"))
    enlace_raw  <- get_first_attr(b, c("a.VDXfz", "a"), "href")
    enlace      <- limpiar_enlace(enlace_raw)
    fuente      <- get_first_text(b, c("div.SVJrMe a", "div.CEMjEf span", "span.xQ82C.e8fRJf", "span.wmnc8c", "div.NUnG9d span"))
    fecha_texto <- get_first_text(b, c("time", "span.WG9SHc span", "span.OSrXXb", "div.OSrXXb"))
    fecha_iso   <- get_first_attr(b, c("time"), "datetime")
    resumen     <- get_first_text(b, c("div.GI74Re", "div.Y3v8qd", "div.gG0TJc", "div.bNeAZd"))
    
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
    dplyr::distinct(enlace, .keep_all = TRUE)
}

## 3.5 Extracción de cuerpo con selectores semánticos y fallback ----
extraer_cuerpo_noticia <- function(url, resumen_fallback) {
  if (is.na(url) || url == "") return(resumen_fallback)
  
  tryCatch({
    resp <- httr::GET(
      url = url,
      httr::add_headers(
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language" = "es-CO,es;q=0.9"
      ),
      httr::timeout(10)
    )
    
    if (httr::status_code(resp) != 200) return(resumen_fallback)
    
    html_doc <- rvest::read_html(httr::content(resp, as = "text", encoding = "UTF-8"))
    
    # 1. Intentar primero con selectores semánticos de artículo
    nodos_articulo <- rvest::html_elements(
      html_doc,
      "article p, div.article-body p, div.story-contents p, div[itemprop='articleBody'] p"
    )
    
    # 2. Si no encuentra o es muy corto, recurrir a todos los párrafos <p>
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

# 4. Loop Principal de Scraping con Checkpointing Incremental ----

ejecutar_scraping_localidades <- function(headless = FALSE, max_paginas = max_paginas_por_mes) {
  message(">>> [RSelenium] Configurando opciones antibot y arrancando ChromeDriver...")
  
  extra_caps <- list(
    chromeOptions = list(
      args = c(
        "--disable-blink-features=AutomationControlled",
        "--disable-infobars",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--window-size=1920,1080",
        "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      ),
      prefs = list(
        "profile.default_content_setting_values.notifications" = 2
      )
    )
  )
  
  if (headless) {
    extra_caps$chromeOptions$args <- c(extra_caps$chromeOptions$args, "--headless=new")
  }
  
  rD <- RSelenium::rsDriver(
    browser    = "chrome",
    chromever  = NULL, # Usa la versión instalada de Chrome
    port       = netstat::free_port(),
    verbose    = FALSE,
    check      = FALSE,
    phantomver = NULL,
    extraCapabilities = extra_caps
  )
  
  remDr <- rD$client
  on.exit({
    try(remDr$close(), silent = TRUE)
    try(rD$server$stop(), silent = TRUE)
    message(">>> Sesión de RSelenium cerrada correctamente.")
  })
  
  # Inyección antibot de evasión de webdriver
  try({
    remDr$navigate("https://www.google.com")
    remDr$executeScript("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
    aceptar_consentimiento(remDr)
  }, silent = TRUE)
  
  total_chunks_procesados <- 0
  
  for (loc in localidades) {
    consulta <- construir_consulta_google(loc)
    message(paste0("\n========================================================"))
    message(paste0("📍 Localidad en proceso: ", loc))
    message(paste0("   Consulta: ", consulta))
    message(paste0("========================================================"))
    
    for (i_mes in seq_along(inicios_mes)) {
      dmin <- inicios_mes[i_mes]
      dmax <- fines_mes[i_mes]
      mes_str <- format(dmin, "%Y-%m")
      
      nombre_limpio <- tolower(stringi::stri_trans_general(loc, "Latin-ASCII"))
      nombre_limpio <- gsub("[^a-zA-Z0-9]", "_", nombre_limpio)
      nombre_limpio <- gsub("_+", "_", nombre_limpio)
      
      archivo_chunk <- file.path(
        ruta_noticias_raw,
        paste0("chunk_", nombre_limpio, "_", format(dmin, "%Y_%m"), ".parquet")
      )
      
      # 1. Control de checkpointing directo: si el chunk ya existe en disco, se omite
      if (file.exists(archivo_chunk)) {
        next
      }
      
      # 2. Control de cobertura histórica: si el mes ya está cubierto en la base validada, se omite
      if (file.exists(archivo_cobertura)) {
        saltar_mes <- FALSE
        try({
          meta <- jsonlite::fromJSON(archivo_cobertura)
          loc_norm <- tolower(stringi::stri_trans_general(loc, "Latin-ASCII"))
          loc_match <- purrr::keep(meta$localidades, function(l) {
            nombre_loc_meta <- if (is.data.frame(l)) l$localidad[1] else l$localidad
            tolower(stringi::stri_trans_general(nombre_loc_meta, "Latin-ASCII")) == loc_norm
          })
          if (length(loc_match) > 0) {
            meses_loc <- if (is.data.frame(loc_match[[1]])) loc_match[[1]]$meses_cubiertos[[1]] else loc_match[[1]]$meses_cubiertos
            if (mes_str %in% meses_loc) {
              saltar_mes <- TRUE
            }
          }
        }, silent = TRUE)
        
        if (saltar_mes) {
          next
        }
      }
      
      message(paste0("  🔄 Scrapeando: ", loc, " | Mes: ", mes_str, "..."))
      datos_mes <- list()
      start     <- 0L
      
      for (i_pag in 1:max_paginas) {
        url <- build_google_news_url(consulta, dmin, dmax, start = start, hl = hl, gl = gl)
        
        tryCatch({
          remDr$navigate(url)
          aceptar_consentimiento(remDr)
          
          # Detección de CAPTCHA
          page_html <- try(remDr$getPageSource()[[1]], silent = TRUE)
          if (!inherits(page_html, "try-error") && str_detect(page_html, regex("unusual traffic|recaptcha", ignore_case = TRUE))) {
            warning("\n🚨 ALERTA: CAPTCHA detectado. Resuelve el desafío en la ventana de Chrome.")
            flush.console()
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
        }, error = function(e) {
          warning(paste0("    ⚠ Error en página ", i_pag, ": ", e$message))
        })
      }
      
      # Guardar el chunk obtenido (o vacío para registrar completitud)
      if (length(datos_mes) > 0) {
        chunk_df <- dplyr::bind_rows(datos_mes) |>
          dplyr::distinct(enlace, .keep_all = TRUE)
        
        # Extracción opcional del cuerpo del artículo
        message(paste0("     Descargando cuerpo para ", nrow(chunk_df), " artículos..."))
        chunk_df$cuerpo <- purrr::map2_chr(chunk_df$enlace, chunk_df$resumen, extraer_cuerpo_noticia)
        
        arrow::write_parquet(chunk_df, archivo_chunk)
        message(paste0("  ✔ Chunk guardado: ", basename(archivo_chunk), " (", nrow(chunk_df), " noticias)"))
      } else {
        vacio_df <- tibble::tibble(
          localidad = loc, consulta = consulta, titulo = character(0),
          resumen = character(0), fuente = character(0), fecha_texto = character(0),
          fecha_iso = character(0), enlace = character(0), fecha_chunk_desde = as.Date(character(0)),
          fecha_chunk_hasta = as.Date(character(0)), pagina = integer(0), cuerpo = character(0)
        )
        arrow::write_parquet(vacio_df, archivo_chunk)
        message(paste0("  ℹ Chunk registrado (0 noticias encontradas): ", basename(archivo_chunk)))
      }
      
      total_chunks_procesados <- total_chunks_procesados + 1
      # Pausa breve entre meses
      Sys.sleep(runif(1, 2.0, 4.0))
    }
  }
  
  message(paste0("\n✔ Scraping completado. Total nuevos chunks procesados: ", total_chunks_procesados))
}

# 5. Consolidación y Actualización de Cobertura ----

consolidar_noticias_scraping <- function() {
  message(">>> [Consolidación] Leyendo base histórica y nuevos chunks...")
  
  # 1. Base histórica existente
  df_historico <- tibble::tibble()
  if (file.exists(archivo_consolidado)) {
    df_historico <- arrow::read_parquet(archivo_consolidado)
    message(paste0("  ✔ Base histórica cargada: ", format(nrow(df_historico), big.mark = ","), " noticias."))
  }
  
  # 2. Chunks adicionales en data/raw/noticias/
  archivos_chunks <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)
  df_nuevos <- tibble::tibble()
  
  if (length(archivos_chunks) > 0) {
    df_nuevos <- purrr::map_dfr(archivos_chunks, function(f) {
      tryCatch(arrow::read_parquet(f), error = function(e) tibble::tibble())
    }) |>
      dplyr::filter(!is.na(titulo) & titulo != "")
    message(paste0("  ✔ Chunks adicionales leídos: ", format(nrow(df_nuevos), big.mark = ","), " noticias."))
  }
  
  # 3. Fusión y deduplicación por enlace limpio y título
  noticias_total <- dplyr::bind_rows(df_historico, df_nuevos) |>
    dplyr::filter(!is.na(enlace) & enlace != "") |>
    dplyr::distinct(enlace, .keep_all = TRUE) |>
    dplyr::distinct(titulo, .keep_all = TRUE)
  
  # 4. Normalización de campos clave
  noticias_total <- noticias_total |>
    dplyr::mutate(
      fuente = ifelse(is.na(fuente) | fuente == "", sub("^https?://([^/]+).*$", "\\1", enlace), fuente)
    )
  
  # 5. Exportar base unificada
  arrow::write_parquet(noticias_total, archivo_consolidado)
  saveRDS(noticias_total, archivo_consol_rds)
  
  message(paste0("\n✔ Base consolidada actualizada exitosamente:"))
  message(paste0("  - Archivo Parquet: ", archivo_consolidado))
  message(paste0("  - Archivo RDS:     ", archivo_consol_rds))
  message(paste0("  - Total noticias únicas: ", format(nrow(noticias_total), big.mark = ",")))
  
  # 6. Actualizar cobertura_historica.json
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
      rango_global = list(
        inicio = as.character(min(as.Date(noticias_total$fecha_chunk_desde), na.rm = TRUE)),
        fin    = as.character(max(as.Date(noticias_total$fecha_chunk_desde), na.rm = TRUE))
      ),
      localidades = split(cobertura, seq_len(nrow(cobertura)))
    )
    
    jsonlite::write_json(metadatos, archivo_cobertura, pretty = TRUE, auto_unbox = TRUE)
    message(paste0("  ✔ Metadatos de cobertura actualizados en: ", archivo_cobertura))
  }, silent = TRUE)
  
  return(invisible(noticias_total))
}

# 6. Ejecución Directa ----
if (!interactive()) {
  message("Para iniciar la recolección ejecute en R:")
  message("  source('scripts/01_ingesta/02_scraping_noticias/scraping_google_news.R')")
  message("  ejecutar_scraping_localidades()")
  message("  consolidar_noticias_scraping()")
}
