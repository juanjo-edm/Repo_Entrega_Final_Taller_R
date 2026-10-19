# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/scraping_google_news.R
# ROL: Web Scraping de Noticias en Google News mediante RSelenium y Checkpointing
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# DESCRIPCIÓN GENERAL:
# Este script automatiza la extracción de artículos de prensa y noticias sobre
# criminalidad (hurtos, robos, atracos, inseguridad) para las 19 localidades
# urbanas de Bogotá D.C. en la pestaña de noticias de Google Search (tbm=nws).
#
# CARACTERÍSTICAS PRINCIPALES:
# 1. Horizonte Temporal Amplio (2022–2026):
#    Permite extraer información mensual continua desde enero de 2022 hasta
#    septiembre de 2026 (57 meses calendario).
# 2. Control Incremental Inteligente (Checkpointing):
#    Antes de consultar a Google, verifica si el mes de la localidad ya fue
#    procesado en data/raw/noticias/ o en la base histórica validada.
# 3. Dos Modos de Operación:
#    - 'faltantes': Completa únicamente los periodos pendientes (ej. Oct 2025 a Sep 2026).
#    - 'enriquecer': Re-escanea meses previos con consultas optimizadas para rescatar
#                    noticias omitidas por filtros anteriores sin duplicar registros.
# 4. Evasión Antibot y Resiliencia en Navegador:
#    Inyección de JavaScript para enmascarar navigator.webdriver, pausas con jitter
#    humano aleatorio, manejo automático de cookies y detección interactiva de CAPTCHA.
# 5. Calidad y Normalización Textual:
#    Limpieza de URLs con tracking, extracción semántica del cuerpo del artículo
#    y filtros de exclusión deportiva para evitar sesgos en casos homónimos (Santa Fe).
#
# GUÍA RÁPIDA DE USO:
#   source(here::here("scripts", "01_ingesta", "02_scraping_noticias", "scraping_google_news.R"))
#   ejecutar_scraping_localidades(modo = "faltantes")   # 1. Descarga automática
#   consolidar_noticias_scraping()                      # 2. Fusión y deduplicación
#   auditar_corpus_noticias()                           # 3. Diagnóstico de calidad
# ==============================================================================

# 1. Configuración de Entorno y Dependencias ----

## 1.1 Opciones globales y reproducibilidad ----
# Evitar notación científica en IDs y fijar semilla estocástica
options(scipen = 999)
set.seed(20261014)

## 1.2 Verificación e instalación de paquetes requeridos ----
librerias_requeridas <- c(
  "here", "conflicted", "RSelenium", "wdman", "netstat", "arrow", "readr",
  "dplyr", "tidyr", "stringr", "stringi", "glue", "lubridate",
  "rvest", "httr", "purrr", "jsonlite"
)

for (pkg in librerias_requeridas) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(paste0("Instalando paquete faltante: ", pkg))
    install.packages(pkg)
  }
}

suppressPackageStartupMessages({
  library(here)        # Rutas relativas seguras referenciadas a la raíz del proyecto
  library(conflicted)  # Resolución estricta y transparente de colisiones de funciones
  library(RSelenium)   # Control automatizado de navegadores web (WebDriver)
  library(wdman)       # Gestor directo de binarios ChromeDriver sin Selenium Server
  library(netstat)     # Detección dinámica de puertos libres de red para Selenium
  library(arrow)       # Lectura y escritura eficiente en formato columnar Parquet
  library(readr)       # Lectura y exportación rápida de tablas rectangulares
  library(dplyr)       # Transformación, filtrado y agregación de datos
  library(tidyr)       # Ordenamiento y estructuración ordenada de datos (tidy data)
  library(stringr)     # Manipulación consistente de cadenas y expresiones regulares
  library(stringi)     # Normalización de caracteres internacionales y remoción de acentos
  library(glue)        # Interpolación limpia y legible de texto y variables
  library(lubridate)   # Manipulación robusta de fechas, meses y rangos temporales
  library(rvest)       # Parseo de HTML y extracción de selectores CSS
  library(httr)        # Peticiones HTTP con control de encabezados y timeouts
  library(purrr)       # Programación funcional y aplicación de mapeos sobre listas
  library(jsonlite)    # Serialización y lectura de metadatos de cobertura en JSON
})

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
# Se fuerza el uso de las versiones de {dplyr} para evitar discrepancias con stats o base
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

# Asegurar existencia del directorio de almacenamiento bruto
if (!dir.exists(ruta_noticias_raw)) {
  dir.create(ruta_noticias_raw, recursive = TRUE)
}

# 2. Configuración de Parámetros y Consultas Booleanas ----

## 2.1 Catálogo canónico de las 19 localidades urbanas ----
# Se excluye deliberadamente Sumapaz (localidad 20) por ser enteramente rural
# y carecer de dinamismo en noticias sobre hurtos urbanos.
localidades <- c(
  "USAQUÉN", "CHAPINERO", "SANTA FE", "SAN CRISTÓBAL", "USME",
  "TUNJUELITO", "BOSA", "KENNEDY", "FONTIBÓN", "ENGATIVÁ",
  "SUBA", "BARRIOS UNIDOS", "TEUSAQUILLO", "LOS MÁRTIRES",
  "ANTONIO NARIÑO", "PUENTE ARANDA", "LA CANDELARIA", 
  "RAFAEL URIBE URIBE", "CIUDAD BOLÍVAR"
)

## 2.2 Constructor de consultas optimizadas con sinónimos y exclusión ----
#' Construye la cadena de consulta booleana para Google Search
#'
#' @description
#' Genera una búsqueda de alta precisión que combina sinónimos de criminalidad
#' con la ciudad obligatoria ("Bogotá") y el nombre de la localidad.
#' En el caso particular de "Santa Fe", agrega términos negativos de exclusión
#' para omitir noticias de fútbol que contaminarían el posterior análisis de polaridad.
#'
#' @param localidad Cadena de texto con el nombre de la localidad.
#' @return Cadena de texto con la consulta formateada para Google.
#' @examples
#' construir_consulta_google("KENNEDY")
#' construir_consulta_google("SANTA FE")
construir_consulta_google <- function(localidad) {
  delitos_kw <- '("hurto" OR "hurtos" OR "robo" OR "robos" OR "atraco" OR "atracos" OR "inseguridad")'
  loc_nombre <- stringr::str_to_title(tolower(localidad))
  
  # Regla de exclusión deportiva:
  # El club 'Independiente Santa Fe' genera ruido frecuente con términos de confrontación
  # (ej. 'derrota', 'ataque del rival', 'golpe') que no corresponden a criminalidad real.
  if (tolower(loc_nombre) == "santa fe") {
    return(glue::glue('{delitos_kw} "Bogotá" "{loc_nombre}" -fútbol -liga -campín -dimayor -cardenal'))
  }
  
  glue::glue('{delitos_kw} "Bogotá" "{loc_nombre}"')
}

## 2.3 Rango temporal mensual (Enero 2022 a Septiembre 2026) ----
fecha_inicio <- as.Date("2022-01-01")
fecha_fin    <- as.Date("2026-09-30")

# Secuencia de primeros días de mes
inicios_mes <- seq(from = floor_date(fecha_inicio, "month"),
                   to   = floor_date(fecha_fin, "month"),
                   by   = "1 month")

# Secuencia correspondiente de últimos días de mes
fines_mes   <- pmin(inicios_mes %m+% months(1) - days(1), fecha_fin)

## 2.4 Parámetros de navegación web y simulación humana ----
hl                  <- "es-419" # Idioma: Español Latinoamérica
gl                  <- "CO"     # Geolocalización: Colombia
max_paginas_por_mes <- 15       # Hasta 15 páginas SERP (aprox. 150 noticias por mes/localidad)
espera_min          <- 3.0      # Pausa mínima en segundos entre peticiones
espera_max          <- 6.0      # Pausa máxima en segundos (jitter aleatorio)

#' Formatea un objeto Date al formato MM/DD/YYYY requerido por Google tbs
formatear_mmddyyyy <- function(fecha) format(as.Date(fecha), "%m/%d/%Y")

#' Construye la URL completa de búsqueda en Google News con filtro temporal
#'
#' @param query Consulta en texto plano (se codifica internamente).
#' @param dmin Fecha inicial del intervalo.
#' @param dmax Fecha final del intervalo.
#' @param start Índice del resultado inicial para paginación (0, 10, 20...).
#' @param hl Código de idioma.
#' @param gl Código de país.
#' @return URL absoluta lista para navegar.
build_google_news_url <- function(query, dmin, dmax, start = 0, hl = "es-419", gl = "CO") {
  q      <- utils::URLencode(query, reserved = TRUE)
  cd_min <- formatear_mmddyyyy(dmin)
  cd_max <- formatear_mmddyyyy(dmax)
  
  # Parámetros clave de Google:
  # tbm=nws        -> Pestaña de Noticias
  # tbs=cdr:1,...  -> Rango personalizado de fechas
  # start=N        -> Paginación
  glue::glue(
    "https://www.google.com/search?q={q}",
    "&tbm=nws&hl={hl}&gl={gl}",
    "&tbs=cdr:1,cd_min:{cd_min},cd_max:{cd_max}",
    "&start={start}"
  )
}

# 3. Funciones de Extracción y Resiliencia en Navegador ----

## 3.1 Gestión de consentimiento de cookies de Google ----
#' Detecta y pulsa el botón de aceptación de cookies si aparece en pantalla
#' @param remDr Instancia del cliente remoto de RSelenium.
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
#' Busca el primer texto disponible entre un vector de selectores CSS candidatos
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

#' Busca el primer atributo disponible entre un vector de selectores CSS candidatos
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

## 3.3 Limpieza de URL de seguimiento y resolución de redirectores ----
#' Normaliza URLs eliminando redirectores de Google y parámetros UTM de tracking
limpiar_enlace <- function(url) {
  if (is.na(url) || url == "") return(NA_character_)
  
  # Si Google devuelve un enlace encapsulado en su redirector (/url?q=...)
  if (grepl("/url\\?q=", url)) {
    url <- sub("^.*/url\\?q=([^&]+).*$", "\\1", url)
    url <- utils::URLdecode(url)
  }
  
  # Remover parámetros de seguimiento y analítica (utm, ref, fbclid)
  sub("\\?(utm_|ref_|fbclid).*", "", url)
}

## 3.4 Extracción estructurada de una página de resultados SERP ----
#' Parsea los contenedores de artículos en una página de resultados de Google News
#'
#' @param remDr Cliente RSelenium activo.
#' @param consulta Texto de la consulta ejecutada.
#' @param localidad Nombre de la localidad correspondiente.
#' @param dmin Fecha inicial del mes.
#' @param dmax Fecha final del mes.
#' @param pagina_idx Índice de la página procesada (1, 2, ...).
#' @return Tibble con las noticias extraídas en la página actual.
extraer_pagina_serp <- function(remDr, consulta, localidad, dmin, dmax, pagina_idx) {
  # Pausa humana aleatoria para evitar detección por cadencia fija
  Sys.sleep(runif(1, espera_min, espera_max))
  
  # Selectores CSS modernos que utiliza Google para los contenedores de noticias
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

## 3.5 Descarga de cuerpo textual con selectores semánticos y fallback ----
#' Extrae el texto completo del artículo desde la URL original
#'
#' @description
#' Hace una petición HTTP con timeout de 10s buscando selectores semánticos
#' (<article>, div.article-body) para ignorar pies de página, cookies y menús.
#' Si el sitio bloquea la petición o el contenido es muy breve, retorna el
#' resumen de Google News como respaldo confiable (fallback).
#'
#' @param url Dirección web del artículo de prensa.
#' @param resumen_fallback Texto del resumen de Google en caso de fallo.
#' @return Cadena de texto con el cuerpo limpio o el fallback.
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
    
    # Prioridad 1: Selectores semánticos de contenido editorial
    nodos_articulo <- rvest::html_elements(
      html_doc,
      "article p, div.article-body p, div.story-contents p, div[itemprop='articleBody'] p"
    )
    
    # Prioridad 2: Si no hay marcas semánticas, extraer párrafos generales <p>
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

# 4. Orquestación del Scraping con Control de Checkpoints ----

#' Ejecuta el ciclo completo de recolección de noticias por localidad y mes
#'
#' @param modo Cadena de texto:
#'   - "faltantes" (por defecto): Descarga únicamente los meses pendientes hasta 2026-09.
#'   - "enriquecer": Re-escanea meses cubiertos para rescatar noticias con la nueva sintaxis.
#' @param localidades_objetivo Vector de localidades a procesar (por defecto las 19).
#' @param headless Booleano: FALSE abre la ventana interactiva de Chrome (recomendado para resolver CAPTCHAs).
#' @param max_paginas Número máximo de páginas SERP a explorar por cada mes (por defecto 15).
#' @param rango_meses Vector opcional de fechas inicio de mes para pruebas acotadas.
#' @return NULL (los datos se persisten atómicamente en disco en cada iteración).
ejecutar_scraping_localidades <- function(modo = c("faltantes", "enriquecer"),
                                         localidades_objetivo = localidades,
                                         headless = FALSE,
                                         max_paginas = max_paginas_por_mes,
                                         rango_meses = NULL) {
  
  modo <- match.arg(modo)
  message(paste0("\n========================================================"))
  message(paste0("🚀 INICIANDO SCRAPER DE GOOGLE NEWS EN MODO: '", toupper(modo), "'"))
  message(paste0("   Localidades a procesar: ", length(localidades_objetivo)))
  message(paste0("========================================================"))
  
  # Configuración de capacidades avanzadas de Chrome (antidetección y estabilidad)
  extra_caps <- list(
    chromeOptions = list(
      args = c(
        "--disable-blink-features=AutomationControlled", # Oculta la bandera interna de Selenium
        "--disable-infobars",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--window-size=1920,1080",
        "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      ),
      prefs = list(
        "profile.default_content_setting_values.notifications" = 2 # Desactivar popups de notificaciones
      )
    )
  )
  
  if (headless) {
    extra_caps$chromeOptions$args <- c(extra_caps$chromeOptions$args, "--headless=new")
  }
  
  # Iniciar ChromeDriver nativo directamente (evita fallos de binman_seleniumserver y Java)
  puerto <- netstat::free_port()
  message(paste0(">>> Conectando ChromeDriver directo en puerto local: ", puerto))
  
  cDrv <- wdman::chrome(
    port    = puerto,
    check   = FALSE,
    verbose = FALSE
  )
  
  remDr <- RSelenium::remoteDriver(
    remoteServerAddr  = "localhost",
    port              = puerto,
    browserName       = "chrome",
    extraCapabilities = extra_caps
  )
  
  Sys.sleep(1.5)
  remDr$open(silent = TRUE)
  
  # Asegurar el cierre del navegador y del proceso ChromeDriver al finalizar o ante interrupción
  on.exit({
    try(remDr$close(), silent = TRUE)
    try(cDrv$stop(), silent = TRUE)
    message(">>> [RSelenium] Proceso ChromeDriver finalizado y puerto liberado.")
  })
  
  # Inyección de script para ocultar la propiedad navigator.webdriver
  try({
    remDr$navigate("https://www.google.com")
    remDr$executeScript("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
    aceptar_consentimiento(remDr)
  }, silent = TRUE)
  
  # Definición de meses a recorrer
  meses_a_procesar <- if (is.null(rango_meses)) inicios_mes else as.Date(rango_meses)
  fines_a_procesar <- pmin(meses_a_procesar %m+% months(1) - days(1), fecha_fin)
  
  total_chunks_procesados <- 0
  
  # Iteración principal por localidad
  for (loc in localidades_objetivo) {
    consulta <- construir_consulta_google(loc)
    message(paste0("\n--------------------------------------------------------"))
    message(paste0("📍 Localidad: ", loc))
    message(paste0("   Consulta:  ", consulta))
    message(paste0("--------------------------------------------------------"))
    
    # Iteración mensual
    for (i_mes in seq_along(meses_a_procesar)) {
      dmin <- meses_a_procesar[i_mes]
      dmax <- fines_a_procesar[i_mes]
      mes_str <- format(dmin, "%Y-%m")
      
      # Normalizar nombre para archivo seguro en disco
      nombre_limpio <- tolower(stringi::stri_trans_general(loc, "Latin-ASCII"))
      nombre_limpio <- gsub("[^a-zA-Z0-9]", "_", nombre_limpio)
      nombre_limpio <- gsub("_+", "_", nombre_limpio)
      
      prefijo_chunk <- if (modo == "enriquecer") "chunk_enriquecido_" else "chunk_"
      archivo_chunk <- file.path(
        ruta_noticias_raw,
        paste0(prefijo_chunk, nombre_limpio, "_", format(dmin, "%Y_%m"), ".parquet")
      )
      
      # Verificación de Checkpoint en modo 'faltantes'
      if (modo == "faltantes") {
        # 1. Si el chunk ya fue descargado previamente en esta sesión o una anterior:
        if (file.exists(archivo_chunk)) {
          next
        }
        
        # 2. Si el mes ya se encuentra cubierto dentro de cobertura_historica.json:
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
          
          if (saltar_mes) next
        }
      } else if (modo == "enriquecer") {
        # En modo enriquecer, omitir solo si este chunk enriquecido ya se guardó
        if (file.exists(archivo_chunk)) next
      }
      
      message(paste0("  🔄 Scrapeando: ", loc, " | Mes: ", mes_str, "..."))
      datos_mes <- list()
      start     <- 0L
      
      # Recorrido de páginas SERP para el mes en curso
      for (i_pag in 1:max_paginas) {
        url <- build_google_news_url(consulta, dmin, dmax, start = start, hl = hl, gl = gl)
        
        tryCatch({
          remDr$navigate(url)
          aceptar_consentimiento(remDr)
          
          # Detección y manejo interactivo de CAPTCHA
          page_html <- try(remDr$getPageSource()[[1]], silent = TRUE)
          if (!inherits(page_html, "try-error") && str_detect(page_html, regex("unusual traffic|recaptcha", ignore_case = TRUE))) {
            warning("\n🚨 ATENCIÓN: CAPTCHA detectado. Por favor resuélvelo en la ventana abierta de Chrome.")
            flush.console()
            Sys.sleep(30) # Espera 30 segundos para permitir resolución manual
            remDr$navigate(url)
            aceptar_consentimiento(remDr)
          }
          
          df_pag <- extraer_pagina_serp(remDr, consulta, loc, dmin, dmax, pagina_idx = i_pag)
          
          # Si no hay más noticias en la página actual, terminar el mes
          if (nrow(df_pag) == 0) {
            break
          } else {
            datos_mes[[length(datos_mes) + 1]] <- df_pag
            start <- start + 10L # Avanzar al siguiente bloque de 10 noticias
          }
        }, error = function(e) {
          warning(paste0("    ⚠ Error capturado en página ", i_pag, ": ", e$message))
        })
      }
      
      # Guardar el lote mensual en formato Parquet atómico
      if (length(datos_mes) > 0) {
        chunk_df <- dplyr::bind_rows(datos_mes) |>
          dplyr::distinct(enlace, .keep_all = TRUE)
        
        message(paste0("     Descargando cuerpo editorial para ", nrow(chunk_df), " noticias..."))
        chunk_df$cuerpo <- purrr::map2_chr(chunk_df$enlace, chunk_df$resumen, extraer_cuerpo_noticia)
        
        arrow::write_parquet(chunk_df, archivo_chunk)
        message(paste0("  ✔ Chunk guardado: ", basename(archivo_chunk), " (", nrow(chunk_df), " noticias)"))
      } else {
        # Registrar un archivo vacío para marcar el mes como consultado sin resultados
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
      # Pausa breve entre meses para moderar el tráfico
      Sys.sleep(runif(1, 2.0, 4.0))
    }
  }
  
  message(paste0("\n✔ Scraping completado exitosamente."))
  message(paste0("   Total de nuevos lotes (chunks) procesados: ", total_chunks_procesados))
}

# 5. Consolidación, Auditoría y Actualización de Metadatos ----

#' Consolida la base histórica con todos los chunks generados y actualiza cobertura
#'
#' @description
#' Lee la base histórica de noticias y todos los archivos 'chunk_*.parquet'
#' generados, aplica deduplicación por enlace limpio y por título exacto,
#' normaliza el campo 'fuente' y sobreescribe los archivos consolidados en
#' Parquet y RDS, actualizando al mismo tiempo 'cobertura_historica.json'.
#'
#' @return Tibble invisible con el consolidado final unificado.
consolidar_noticias_scraping <- function() {
  message("\n>>> [Consolidación] Leyendo base histórica y lotes descargados...")
  
  # 1. Base histórica validada existente
  df_historico <- tibble::tibble()
  if (file.exists(archivo_consolidado)) {
    df_historico <- arrow::read_parquet(archivo_consolidado)
    message(paste0("  ✔ Base previa cargada: ", format(nrow(df_historico), big.mark = ","), " noticias."))
  }
  
  # 2. Lotes adicionales en data/raw/noticias/
  archivos_chunks <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)
  df_nuevos <- tibble::tibble()
  
  if (length(archivos_chunks) > 0) {
    df_nuevos <- purrr::map_dfr(archivos_chunks, function(f) {
      tryCatch(arrow::read_parquet(f), error = function(e) tibble::tibble())
    }) |>
      dplyr::filter(!is.na(titulo) & titulo != "")
    message(paste0("  ✔ Chunks adicionales leídos: ", format(nrow(df_nuevos), big.mark = ","), " noticias."))
  }
  
  # 3. Fusión y deduplicación dual (por URL limpia y por título idéntico)
  noticias_total <- dplyr::bind_rows(df_historico, df_nuevos) |>
    dplyr::filter(!is.na(enlace) & enlace != "") |>
    dplyr::distinct(enlace, .keep_all = TRUE) |>
    dplyr::distinct(titulo, .keep_all = TRUE)
  
  # 4. Normalización de dominios y medios
  noticias_total <- noticias_total |>
    dplyr::mutate(
      fuente = ifelse(is.na(fuente) | fuente == "", sub("^https?://([^/]+).*$", "\\1", enlace), fuente)
    )
  
  # 5. Exportar la base unificada en Parquet y RDS para máxima portabilidad
  arrow::write_parquet(noticias_total, archivo_consolidado)
  saveRDS(noticias_total, archivo_consol_rds)
  
  message(paste0("\n✔ Base de datos consolidada actualizada:"))
  message(paste0("  - Parquet: ", archivo_consolidado))
  message(paste0("  - RDS:     ", archivo_consol_rds))
  message(paste0("  - Total noticias únicas validadas: ", format(nrow(noticias_total), big.mark = ",")))
  
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
      rango_global = list(
        inicio = as.character(min(as.Date(noticias_total$fecha_chunk_desde), na.rm = TRUE)),
        fin    = as.character(max(as.Date(noticias_total$fecha_chunk_desde), na.rm = TRUE))
      ),
      localidades = split(cobertura, seq_len(nrow(cobertura)))
    )
    
    jsonlite::write_json(metadatos, archivo_cobertura, pretty = TRUE, auto_unbox = TRUE)
    message(paste0("  ✔ Registro de metadatos actualizado en: ", archivo_cobertura))
  }, silent = TRUE)
  
  return(invisible(noticias_total))
}

#' Genera un reporte diagnóstico en consola sobre el estado del corpus consolidado
#'
#' @return Tibble invisible con el dataset leído.
auditar_corpus_noticias <- function() {
  if (!file.exists(archivo_consolidado)) {
    message("⚠ No se encontró el archivo consolidado en data/raw/.")
    return(NULL)
  }
  
  df <- arrow::read_parquet(archivo_consolidado)
  
  cat("\n=======================================================\n")
  cat("📊 AUDITORÍA DEL CORPUS DE NOTICIAS CONSOLIDADO\n")
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
  
  cat("\nPrincipales medios de comunicación:\n")
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

# 6. Ejecución Automática del Pipeline de Scraping ----

#' Ejecuta el pipeline completo de scraping, consolidación y auditoría
#'
#' @param modo "faltantes" (descarga solo meses pendientes hasta 2026-09) o "enriquecer"
#' @param headless Booleano: FALSE abre Chrome visible (recomendado para resolver CAPTCHAs)
#' @return Tibble invisible con el corpus consolidado final.
ejecutar_pipeline_noticias_completo <- function(modo = "faltantes", headless = FALSE) {
  message("\n==================================================================")
  message("  INICIANDO PIPELINE DE SCRAPING DE GOOGLE NEWS")
  message("==================================================================")
  
  # Paso 1: Ejecutar recolección por localidad y mes
  ejecutar_scraping_localidades(modo = modo, headless = headless)
  
  # Paso 2: Consolidar y actualizar base histórica
  df_consolidado <- consolidar_noticias_scraping()
  
  # Paso 3: Auditar y mostrar métricas en consola
  auditar_corpus_noticias()
  
  return(invisible(df_consolidado))
}

# Auto-ejecución inmediata:
# Si se corre el script directamente con source() o Rscript, inicia la descarga.
# Para cargar únicamente las funciones sin disparar la descarga, definir auto_ejecutar <- FALSE previamente.
if (!exists("auto_ejecutar") || isTRUE(auto_ejecutar)) {
  ejecutar_pipeline_noticias_completo(modo = "faltantes", headless = FALSE)
}
