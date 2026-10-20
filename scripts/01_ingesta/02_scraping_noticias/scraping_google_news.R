# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/scraping_google_news.R
# ROL: Flujo Secuencial de Ingesta y Consolidación de Noticias (Google News RSS)
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# DESCRIPCIÓN DEL FLUJO:
# Este script ejecuta un flujo lineal, secuencial y pedagógico para recolectar,
# limpiar, consolidar y auditar artículos de noticias sobre seguridad ciudadana
# en las 19 localidades urbanas de Bogotá D.C.
#
# DISEÑO PROCEDURAL (SIN FUNCIONES ENVOLVENTES COMPLEJAS):
# El código está organizado para ejecutarse de arriba hacia abajo (o línea por línea
# mediante Ctrl+Enter en RStudio), facilitando su lectura, inspección de variables
# en el Environment y evaluación académica paso a paso:
#
#   - Paso 1: Configuración de librerías, rutas y parámetros del análisis.
#   - Paso 2: Catálogo territorial y funciones auxiliares mínimas de limpieza.
#   - Paso 3: Recolección y descarga de noticias mediante Google News RSS (bucle directo).
#   - Paso 4: Carga y unificación secuencial de chunks y serie histórica.
#   - Paso 5: Deduplicación dual, normalización y delimitación temporal estricta (2022-2026).
#   - Paso 6: Exportación de datos limpios a Parquet, RDS y metadatos JSON.
#   - Paso 7: Diagnóstico, auditoría y control de calidad impresos en consola.
# ==============================================================================


# ==============================================================================
# PASO 1: CONFIGURACIÓN DEL ENTORNO, PAQUETES Y PARÁMETROS GLOBALES
# ==============================================================================

# 1.1 Opciones de sesión y reproducibilidad
# Evitamos notación científica (ej. 1e+05) y fijamos semilla para trazabilidad
options(scipen = 999)
set.seed(20261014)

# 1.2 Verificación e instalación automática de dependencias
paquetes_requeridos <- c(
  "here",        # Manejo de rutas relativas al proyecto
  "conflicted",  # Prevención de ambigüedades entre nombres de funciones
  "arrow",       # Lectura y escritura eficiente en formato columnar Parquet
  "readr",       # Funciones de lectura rápida de datos
  "dplyr",       # Gramática principal de manipulación de datos
  "tidyr",       # Funciones para ordenamiento y pivoteo de datos
  "stringr",     # Manipulación de cadenas de texto y regex
  "stringi",     # Normalización de caracteres y remoción de tildes
  "glue",        # Interpolación clara de cadenas de texto
  "lubridate",   # Manejo avanzado de fechas y calendarios
  "xml2",        # Lectura y parseo del feed XML de Google News RSS
  "rvest",       # Extracción y limpieza de etiquetas HTML
  "httr",        # Peticiones HTTP con control de encabezados y timeouts
  "purrr",       # Aplicación funcional e iteraciones seguras
  "jsonlite"     # Exportación y parseo de archivos JSON
)

for (paquete in paquetes_requeridos) {
  if (!requireNamespace(paquete, quietly = TRUE)) {
    message(paste0("Instalando paquete faltante: ", paquete))
    install.packages(paquete)
  }
}

# 1.3 Carga silenciosa de librerías en la sesión
suppressPackageStartupMessages({
  library(here)
  library(conflicted)
  library(arrow)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(stringi)
  library(glue)
  library(lubridate)
  library(xml2)
  library(rvest)
  library(httr)
  library(purrr)
  library(jsonlite)
})

# 1.4 Reglas explícitas de resolución de conflictos de funciones
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

# 1.5 Definición de rutas relativas con el paquete {here}
# Garantiza que el código funcione de forma idéntica en cualquier máquina o SO
ruta_datos_raw      <- here::here("data", "raw")
ruta_noticias_raw   <- here::here("data", "raw", "noticias")
archivo_consolidado <- here::here("data", "raw", "noticias_google_news_consolidado.parquet")
archivo_consol_rds  <- here::here("data", "raw", "noticias_google_news_consolidado.rds")
archivo_cobertura   <- here::here("data", "raw", "noticias", "cobertura_historica.json")

# Creación del directorio de almacenamiento si no existe
if (!dir.exists(ruta_noticias_raw)) {
  dir.create(ruta_noticias_raw, recursive = TRUE)
}

# 1.6 PARÁMETROS DEL PIPELINE CONFIGURABLES POR EL USUARIO:
# Rango temporal de interés para el proyecto (2022-01-01 a 2026-09-30)
FECHA_INICIO_ANALISIS <- as.Date("2022-01-01")
FECHA_FIN_ANALISIS    <- as.Date("2026-09-30")

# Interruptores de ejecución:
# - EJECUTAR_SCRAPING_RSS: Poner TRUE si se desea volver a interrogar en vivo el feed de Google News
#   Poner FALSE si ya se tienen los chunks descargados y solo se requiere consolidar/limpiar/auditar.
EJECUTAR_SCRAPING_RSS <- FALSE

# - DESCARGAR_CUERPOS_HTML: Poner TRUE si se desea navegar a cada noticia para raspar el cuerpo completo
#   Poner FALSE para usar el resumen estructurado oficial provisto por el RSS (recomendado por velocidad).
DESCARGAR_CUERPOS_HTML <- FALSE


# ==============================================================================
# PASO 2: CATÁLOGO TERRITORIAL Y FUNCIONES AUXILIARES DE LIMPIEZA
# ==============================================================================

# 2.1 Definición de las 19 localidades urbanas de Bogotá D.C.
# (Se excluye Sumapaz por ser 100% rural y no presentar reporte continuo en prensa urbana)
localidades <- c(
  "USAQUÉN", "CHAPINERO", "SANTA FE", "SAN CRISTÓBAL", "USME",
  "TUNJUELITO", "BOSA", "KENNEDY", "FONTIBÓN", "ENGATIVÁ",
  "SUBA", "BARRIOS UNIDOS", "TEUSAQUILLO", "LOS MÁRTIRES",
  "ANTONIO NARIÑO", "PUENTE ARANDA", "LA CANDELARIA", 
  "RAFAEL URIBE URIBE", "CIUDAD BOLÍVAR"
)

# 2.2 Funciones auxiliares esenciales (bien documentadas y modulares)

#' Construye la consulta de búsqueda booleana para Google News RSS
#'
#' @param localidad Nombre de la localidad en texto plano.
#' @return Cadena formateada con términos booleanos y filtros temáticos.
construir_consulta_rss <- function(localidad) {
  # Agrupación de sinónimos de delitos asociados a seguridad ciudadana
  delitos_kw <- '(hurto OR robo OR atraco OR asalto OR inseguridad)'
  loc_nombre <- stringr::str_to_title(tolower(localidad))
  
  # Exclusión de noticias deportivas para la localidad de Santa Fe
  # (Evita confundir noticias del club de fútbol Independiente Santa Fe con la localidad)
  if (tolower(loc_nombre) == "santa fe") {
    return(glue::glue('{delitos_kw} Bogota "{loc_nombre}" -futbol -liga -campin -dimayor -cardenal'))
  }
  
  # Consulta estándar con la localidad encomillada para búsqueda exacta
  glue::glue('{delitos_kw} Bogota "{loc_nombre}"')
}

# Alias para compatibilidad con scripts históricos
construir_consulta_google <- construir_consulta_rss

#' Construye la URL oficial del feed RSS de Google News
#'
#' @param query Cadena de búsqueda.
#' @param hl Idioma (es-419: español latinoamericano).
#' @param gl Región / País (CO: Colombia).
#' @return URL absoluta y codificada hacia news.google.com/rss/search.
build_google_news_url <- function(query, hl = "es-419", gl = "CO", ...) {
  q_enc <- utils::URLencode(query, reserved = TRUE)
  glue::glue("https://news.google.com/rss/search?q={q_enc}&hl={hl}&gl={gl}&ceid={gl}:{hl}")
}

#' Limpia y normaliza URLs eliminando rastreadores y parámetros de analítica
#'
#' @param url Cadena con la URL original.
#' @return URL canónica limpia o NA si la entrada es inválida.
limpiar_enlace <- function(url) {
  if (is.na(url) || url == "") return(NA_character_)
  
  # Si la URL viene encapsulada en el redirector interno de Google /url?q=
  if (grepl("/url\\?q=", url)) {
    url <- sub("^.*/url\\?q=([^&]+).*$", "\\1", url)
    url <- utils::URLdecode(url)
  }
  
  # Remover parámetros analíticos de tracking (Google Analytics UTM, Facebook, etc.)
  url_limpia <- sub("\\?(utm_|ref_|fbclid).*", "", url)
  return(url_limpia)
}

#' Convierte fechas estándar RFC 822 (formato estándar de feeds RSS) a formato Date
#'
#' @param fecha_str Cadena de fecha provista en el feed RSS.
#' @return Objeto Date de R.
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

#' Extrae el cuerpo editorial de una noticia con fallback resiliente al resumen
#'
#' @param url Dirección web del artículo.
#' @param resumen_fallback Texto de respaldo en caso de fallo en la descarga.
#' @return Cadena de texto con el contenido del artículo.
extraer_cuerpo_noticia <- function(url, resumen_fallback) {
  if (is.na(url) || url == "") return(resumen_fallback)
  
  tryCatch({
    peticion <- httr::GET(
      url = url,
      httr::add_headers(
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language" = "es-CO,es;q=0.9"
      ),
      httr::timeout(6)
    )
    
    if (httr::status_code(peticion) != 200) return(resumen_fallback)
    
    pagina_html <- rvest::read_html(httr::content(peticion, as = "text", encoding = "UTF-8"))
    
    # Búsqueda semántica en contenedores estándar de prensa
    parrafos <- rvest::html_elements(
      pagina_html,
      "article p, div.article-body p, div.story-contents p, div[itemprop='articleBody'] p"
    )
    
    if (length(parrafos) == 0) {
      parrafos <- rvest::html_elements(pagina_html, "p")
    }
    
    texto_extraido <- parrafos |>
      rvest::html_text(trim = TRUE) |>
      paste(collapse = " ")
    
    if (nchar(texto_extraido) < 50) return(resumen_fallback)
    return(texto_extraido)
  }, error = function(e) {
    return(resumen_fallback)
  })
}


# ==============================================================================
# CONTROL DE ENTORNO DE PRUEBAS UNITARIAS
# ==============================================================================
# Si el script es invocado desde testthat o un script de pruebas con auto_ejecutar = FALSE,
# se detiene aquí para proveer las funciones sin ejecutar el procesamiento completo.
if (exists("auto_ejecutar") && !isTRUE(auto_ejecutar)) {
  message("ℹ Modo de pruebas activo: funciones auxiliares cargadas exitosamente en memoria.")
  # Se interrumpe la ejecución del resto del script de forma controlada
} else {

  # ============================================================================
  # PASO 3: RECOLECCIÓN SECUENCIAL VÍA GOOGLE NEWS RSS (BUCLE DIRECTO)
  # ============================================================================
  
  if (isTRUE(EJECUTAR_SCRAPING_RSS)) {
    cat("\n==================================================================\n")
    cat("📡 INICIANDO BUCLE DE RECOLECCIÓN VÍA GOOGLE NEWS RSS\n")
    cat(paste0("   Total de localidades a procesar: ", length(localidades), "\n"))
    cat("==================================================================\n\n")
    
    contador_noticias_descargadas <- 0
    
    for (i in seq_along(localidades)) {
      loc_actual <- localidades[i]
      cat(paste0("[", i, "/", length(localidades), "] Procesando localidad: ", loc_actual, "...\n"))
      
      # 3.1 Armar consulta booleana y URL
      consulta_texto <- construir_consulta_rss(loc_actual)
      url_feed       <- build_google_news_url(consulta_texto)
      
      # 3.2 Nombre del archivo chunk particionado
      slug_localidad <- tolower(stringi::stri_trans_general(loc_actual, "Latin-ASCII"))
      slug_localidad <- gsub("[^a-z0-9]", "_", slug_localidad)
      archivo_chunk  <- file.path(ruta_noticias_raw, paste0("chunk_rss_", slug_localidad, ".parquet"))
      
      # 3.3 Petición HTTP y lectura del XML
      intento_descarga <- tryCatch({
        documento_xml <- xml2::read_xml(url_feed)
        elementos_item <- xml2::xml_find_all(documento_xml, "//item")
        
        if (length(elementos_item) > 0) {
          # Extracción vectorial de etiquetas XML
          titulos_vec    <- xml2::xml_text(xml2::xml_find_first(elementos_item, "title"))
          enlaces_vec    <- xml2::xml_text(xml2::xml_find_first(elementos_item, "link"))
          fechas_raw_vec <- xml2::xml_text(xml2::xml_find_first(elementos_item, "pubDate"))
          fuentes_vec    <- xml2::xml_text(xml2::xml_find_first(elementos_item, "source"))
          desc_raw_vec   <- xml2::xml_text(xml2::xml_find_first(elementos_item, "description"))
          
          # Limpiar etiquetas HTML de los resúmenes
          resumenes_vec <- purrr::map_chr(desc_raw_vec, function(texto) {
            if (is.na(texto) || texto == "") return(NA_character_)
            tryCatch(rvest::read_html(texto) |> rvest::html_text(trim = TRUE), error = function(e) texto)
          })
          
          # Parseo de fechas a formato Date
          fechas_convertidas <- purrr::map_vec(fechas_raw_vec, parsear_fecha_rss)
          
          # Construcción del tibble estructurado
          df_loc <- tibble::tibble(
            localidad         = stringr::str_to_title(tolower(loc_actual)),
            consulta          = consulta_texto,
            titulo            = titulos_vec,
            resumen           = resumenes_vec,
            fuente            = fuentes_vec,
            fecha_texto       = fechas_raw_vec,
            fecha_iso         = as.character(fechas_convertidas),
            enlace            = purrr::map_chr(enlaces_vec, limpiar_enlace),
            fecha_chunk_desde = lubridate::floor_date(as.Date(fechas_convertidas), "month"),
            fecha_chunk_hasta = lubridate::ceiling_date(as.Date(fechas_convertidas), "month") - lubridate::days(1),
            pagina            = 1L
          ) |>
            dplyr::filter(!is.na(titulo) & titulo != "") |>
            dplyr::distinct(enlace, .keep_all = TRUE)
          
          # Si se solicita descargar el cuerpo HTML completo:
          if (isTRUE(DESCARGAR_CUERPOS_HTML)) {
            cat("    -> Descargando contenido editorial de cada enlace...\n")
            df_loc$cuerpo <- purrr::map2_chr(df_loc$enlace, df_loc$resumen, extraer_cuerpo_noticia)
          } else {
            df_loc$cuerpo <- df_loc$resumen
          }
          
          # Guardado seguro en disco del chunk
          arrow::write_parquet(df_loc, archivo_chunk)
          cat(paste0("    ✔ ", nrow(df_loc), " noticias guardadas en: ", basename(archivo_chunk), "\n"))
          contador_noticias_descargadas <- contador_noticias_descargadas + nrow(df_loc)
        } else {
          cat("    ℹ No se encontraron noticias recientes en el feed para esta localidad.\n")
        }
      }, error = function(err) {
        cat(paste0("    ⚠ Error consultando ", loc_actual, ": ", err$message, "\n"))
      })
      
      # Pausa prudencial entre peticiones para no saturar conexiones
      Sys.sleep(1.0)
    }
    
    cat(paste0("\n✔ Bucle RSS completado. Total noticias descargadas en esta sesión: ", contador_noticias_descargadas, "\n\n"))
  } else {
    cat("\nℹ Saltando bucle de descarga en vivo (EJECUTAR_SCRAPING_RSS = FALSE). Procesando datos locales existentes...\n")
  }


  # ============================================================================
  # PASO 4: CARGA Y UNIFICACIÓN DE LA BASE HISTÓRICA Y CHUNKS RECIENTES
  # ============================================================================
  
  cat("\n==================================================================\n")
  cat("🔄 PASO 4: CONSOLIDACIÓN Y LECTURA DE CHUNKS EXISTENTES\n")
  cat("==================================================================\n")
  
  # 4.1 Cargar base histórica existente si está presente en disco
  df_base_previa <- tibble::tibble()
  if (file.exists(archivo_consolidado)) {
    cat(paste0("  -> Leyendo base consolidada previa desde: ", basename(archivo_consolidado), "\n"))
    df_base_previa <- arrow::read_parquet(archivo_consolidado)
    cat(paste0("     Artículos previos cargados: ", format(nrow(df_base_previa), big.mark = ","), "\n"))
  }
  
  # 4.2 Cargar todos los chunks Parquet generados en data/raw/noticias/
  archivos_chunks <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)
  cat(paste0("  -> Se detectaron ", length(archivos_chunks), " archivos chunk en: data/raw/noticias/\n"))
  
  df_chunks_nuevos <- tibble::tibble()
  if (length(archivos_chunks) > 0) {
    df_chunks_nuevos <- purrr::map_dfr(archivos_chunks, function(archivo) {
      tryCatch(arrow::read_parquet(archivo), error = function(e) tibble::tibble())
    }) |>
      dplyr::filter(!is.na(titulo) & titulo != "")
    cat(paste0("     Total de registros en chunks: ", format(nrow(df_chunks_nuevos), big.mark = ","), "\n"))
  }
  
  # 4.3 Fusión lineal vertical de ambos conjuntos de datos
  corpus_unificado <- dplyr::bind_rows(df_base_previa, df_chunks_nuevos)
  cat(paste0("  -> Filas totales combinadas antes de limpieza: ", format(nrow(corpus_unificado), big.mark = ","), "\n"))


  # ============================================================================
  # PASO 5: DEDUPLICACIÓN DUAL, NORMALIZACIÓN Y DELIMITACIÓN TEMPORAL (2022-2026)
  # ============================================================================
  
  cat("\n==================================================================\n")
  cat("🧹 PASO 5: DEDUPLICACIÓN DUAL Y DELIMITACIÓN TEMPORAL (2022 A 2026-09)\n")
  cat("==================================================================\n")
  
  corpus_limpio <- corpus_unificado |>
    # 5.1 Eliminar registros sin enlace o sin titular
    dplyr::filter(!is.na(enlace) & enlace != "") |>
    dplyr::filter(!is.na(titulo) & titulo != "") |>
    
    # 5.2 Deduplicación dual:
    # 1º Por enlace web canónico limpio
    dplyr::distinct(enlace, .keep_all = TRUE) |>
    # 2º Por titular idéntico (elimina notas republicadas bajo distintas URLs por agencias)
    dplyr::distinct(titulo, .keep_all = TRUE) |>
    
    # 5.3 Normalización de nombres de medios y fechas
    dplyr::mutate(
      fuente            = ifelse(is.na(fuente) | fuente == "", sub("^https?://([^/]+).*$", "\\1", enlace), fuente),
      fecha_chunk_desde = as.Date(fecha_chunk_desde),
      cuerpo            = ifelse(is.na(cuerpo) | cuerpo == "", resumen, cuerpo)
    ) |>
    
    # 5.4 Delimitación temporal estricta al período de interés generalizable
    dplyr::filter(
      fecha_chunk_desde >= FECHA_INICIO_ANALISIS & fecha_chunk_desde <= FECHA_FIN_ANALISIS
    ) |>
    dplyr::arrange(localidad, fecha_chunk_desde)
  
  cat(paste0("  ✔ Registros únicos validados tras deduplicación y filtros: ", 
             format(nrow(corpus_limpio), big.mark = ","), "\n"))


  # ============================================================================
  # PASO 6: EXPORTACIÓN DE DATASETS Y METADATOS DE COBERTURA
  # ============================================================================
  
  cat("\n==================================================================\n")
  cat("💾 PASO 6: EXPORTACIÓN EN PARQUET, RDS Y METADATOS JSON\n")
  cat("==================================================================\n")
  
  # 6.1 Guardado en formato columnar Parquet (óptimo para lectura rápida y compresión)
  arrow::write_parquet(corpus_limpio, archivo_consolidado)
  cat(paste0("  ✔ Base consolidada en Parquet: ", archivo_consolidado, "\n"))
  
  # 6.2 Guardado en formato nativo R (RDS) para máxima compatibilidad
  saveRDS(corpus_limpio, archivo_consol_rds)
  cat(paste0("  ✔ Base consolidada en RDS:     ", archivo_consol_rds, "\n"))
  
  # 6.3 Generación del archivo JSON de metadatos de auditoría
  try({
    resumen_cobertura <- corpus_limpio |>
      dplyr::group_by(localidad) |>
      dplyr::summarise(
        noticias_consolidadas = n(),
        fecha_min             = as.character(min(as.Date(fecha_chunk_desde), na.rm = TRUE)),
        fecha_max             = as.character(max(as.Date(fecha_chunk_desde), na.rm = TRUE)),
        meses_cubiertos       = list(sort(unique(format(as.Date(fecha_chunk_desde), "%Y-%m")))),
        fuentes_principales   = list(head(names(sort(table(fuente), decreasing = TRUE)), 5)),
        .groups               = "drop"
      )
    
    metadatos_json <- list(
      proyecto                 = "Hurtos y Sentimiento Mediatico en Bogota (2022-2026)",
      fecha_actualizacion      = as.character(Sys.time()),
      total_filas_consolidadas = nrow(corpus_limpio),
      rango_generalizable      = list(
        inicio = as.character(min(as.Date(corpus_limpio$fecha_chunk_desde), na.rm = TRUE)),
        fin    = as.character(max(as.Date(corpus_limpio$fecha_chunk_desde), na.rm = TRUE))
      ),
      localidades              = split(resumen_cobertura, seq_len(nrow(resumen_cobertura)))
    )
    
    jsonlite::write_json(metadatos_json, archivo_cobertura, pretty = TRUE, auto_unbox = TRUE)
    cat(paste0("  ✔ Metadatos de cobertura actualizados en: ", archivo_cobertura, "\n"))
  }, silent = TRUE)


  # ============================================================================
  # PASO 7: AUDITORÍA Y CONTROL DE CALIDAD EN CONSOLA
  # ============================================================================
  
  cat("\n=======================================================\n")
  cat("📊 AUDITORÍA DEL CORPUS DE NOTICIAS CONSOLIDADO (2022-2026)\n")
  cat("=======================================================\n")
  cat(paste0("Total de artículos: ", format(nrow(corpus_limpio), big.mark = ","), "\n"))
  cat(paste0("Rango temporal:     ", min(corpus_limpio$fecha_chunk_desde, na.rm=TRUE), " a ", max(corpus_limpio$fecha_chunk_desde, na.rm=TRUE), "\n"))
  cat(paste0("Medios únicos:      ", length(unique(corpus_limpio$fuente)), "\n\n"))
  
  # Distribución por año
  cat("Distribución por año:\n")
  tabla_año <- corpus_limpio |>
    dplyr::mutate(año = lubridate::year(as.Date(fecha_chunk_desde))) |>
    dplyr::count(año, name = "total_noticias")
  print(as.data.frame(tabla_año), row.names = FALSE)
  
  # Distribución por localidad (Top 10)
  cat("\nNoticias por localidad (Top 10):\n")
  tabla_loc <- corpus_limpio |>
    dplyr::count(localidad, sort = TRUE, name = "total_noticias") |>
    head(10)
  print(as.data.frame(tabla_loc), row.names = FALSE)
  
  # Principales medios de prensa (Top 5)
  cat("\nPrincipales medios de comunicación (Top 5):\n")
  tabla_fuentes <- corpus_limpio |>
    dplyr::count(fuente, sort = TRUE, name = "total_noticias") |>
    head(5)
  print(as.data.frame(tabla_fuentes), row.names = FALSE)
  
  # Control de valores faltantes (NAs)
  cat("\nAuditoría de valores faltantes (NAs):\n")
  cat(paste0("  - Titular: ", sum(is.na(corpus_limpio$titulo)), "\n"))
  cat(paste0("  - Resumen: ", sum(is.na(corpus_limpio$resumen)), "\n"))
  cat(paste0("  - Enlace:  ", sum(is.na(corpus_limpio$enlace)), "\n"))
  cat(paste0("  - Cuerpo:  ", sum(is.na(corpus_limpio$cuerpo)), "\n"))
  cat("=======================================================\n")
  cat("✔ FLUJO DE SCRAPING Y CONSOLIDACIÓN FINALIZADO CON ÉXITO\n")
  cat("=======================================================\n\n")

} # Fin del bloque condicional de ejecución
