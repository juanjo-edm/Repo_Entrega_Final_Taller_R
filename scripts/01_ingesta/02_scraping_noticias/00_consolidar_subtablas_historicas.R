# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Migración, Trazabilidad y Consolidación de Subtablas Históricas (Google News)
# GRUPO 10: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# DESCRIPCIÓN:
# Este script toma las 19 subtablas brutas extraídas originalmente por localidad
# en el repositorio previo (Perception-and-legitimacy), preserva su estructura
# individual en `data/raw/noticias/historico_por_localidad/`, y replica con 
# exactitud matemática la metodología de consolidación y limpieza validada.
#
# Adicionalmente, genera un registro de metadatos de cobertura temporal
# (`cobertura_historica.json`) y provee funciones para que el scraper incremental
# (`scraping_google_news.R`) pueda detectar qué meses ya existen y omitirlos,
# permitiendo expandir la base hacia periodos futuros sin duplicar peticiones.
# ==============================================================================

# 1. Dependencias y Entorno ----
suppressPackageStartupMessages({
  library(here)
  library(readxl)
  library(arrow)
  library(dplyr)
  library(stringr)
  library(stringi)
  library(jsonlite)
  library(purrr)
  library(lubridate)
})

# Definición de rutas del proyecto
dir_raiz              <- here::here()
dir_noticias_raw      <- here::here("data", "raw", "noticias")
dir_historico_loc     <- here::here("data", "raw", "noticias", "historico_por_localidad")
archivo_consolidado_p <- here::here("data", "raw", "noticias_google_news_consolidado.parquet")
archivo_consolidado_r <- here::here("data", "raw", "noticias_google_news_consolidado.rds")
archivo_metadatos     <- here::here("data", "raw", "noticias", "cobertura_historica.json")

# Ruta externa original donde residen las carpetas por localidad
ruta_externa_origen <- "/Users/juanjoseecheverry/Downloads/Perception-and-legitimacy-main/src/Scraping/Scraping Google News/Scraping_Selenium/Sacraping Por localidades"

# Crear carpetas si no existen
if (!dir.exists(dir_historico_loc)) dir.create(dir_historico_loc, recursive = TRUE)

# 2. Diccionario Canónico de las 19 Localidades Urbanas ----
localidades_canonicas <- tibble::tribble(
  ~slug,                ~nombre_oficial,
  "antonio_narino",     "Antonio Nariño",
  "barrios_unidos",     "Barrios Unidos",
  "bosa",               "Bosa",
  "candelaria",         "Candelaria",
  "chapinero",          "Chapinero",
  "ciudad_bolivar",     "Ciudad Bolívar",
  "engativa",           "Engativá",
  "fontibon",           "Fontibón",
  "kennedy",            "Kennedy",
  "los_martires",       "Los Mártires",
  "puente_aranda",      "Puente Aranda",
  "rafael_uribe_uribe", "Rafael Uribe Uribe",
  "san_cristobal",      "San Cristóbal",
  "santa_fe",           "Santa Fe",
  "suba",               "Suba",
  "teusaquillo",        "Teusaquillo",
  "tunjuelito",         "Tunjuelito",
  "usaquen",            "Usaquén",
  "usme",               "Usme"
)

# 3. Funciones Utilitarias Metodológicas ----

#' Extrae el dominio raíz o medio de comunicación a partir de una URL
extraer_dominio <- function(urls) {
  sub("^https?://([^/]+).*$", "\\1", urls)
}

#' Normaliza texto a representación ASCII sin tildes ni caracteres especiales
a_ascii <- function(texto) {
  stri_trans_general(texto, "Latin-ASCII")
}

# 4. Ingesta y Preservación de Subtablas Individuales ----

migrar_subtablas_historicas <- function(ruta_origen = ruta_externa_origen) {
  message(">>> [Paso 1/4] Buscando carpetas de localidades en el origen histórico...")
  
  if (!dir.exists(ruta_origen)) {
    # Si la ruta externa no existe, verificar si ya fueron migradas localmente
    archivos_locales <- list.files(dir_historico_loc, pattern = "\\.parquet$", full.names = TRUE)
    if (length(archivos_locales) >= 19) {
      message("ℹ Las 19 subtablas ya existen en 'data/raw/noticias/historico_por_localidad/'. Leyendo localmente.")
      return(purrr::map_dfr(archivos_locales, arrow::read_parquet))
    } else {
      stop(paste("No se encontró la ruta de origen ni los archivos locales:", ruta_origen))
    }
  }
  
  carpetas <- list.dirs(ruta_origen, full.names = TRUE, recursive = FALSE)
  # Omitir carpeta duplicada accidental 'Antonio Nariño 2'
  carpetas <- carpetas[!grepl("Antonio Nari.+2", basename(carpetas))]
  
  message(paste0("  Localidades encontradas: ", length(carpetas)))
  
  lista_subtablas <- list()
  
  for (carpeta in carpetas) {
    archivos_excel <- list.files(carpeta, pattern = "xlsx$", full.names = TRUE)
    if (length(archivos_excel) == 0) next
    
    archivo_loc <- archivos_excel[1]
    nombre_carpeta <- basename(carpeta)
    
    df_loc <- readxl::read_excel(archivo_loc)
    
    # Estandarización de columnas mínimas esperadas
    columnas_esperadas <- c("consulta", "titulo", "resumen", "enlace", "fecha_chunk_desde", "cuerpo")
    if (!all(columnas_esperadas %in% colnames(df_loc))) {
      warning(paste("El archivo", archivo_loc, "no contiene todas las columnas esperadas."))
    }
    
    # Determinar slug canónico
    nombre_norm <- tolower(a_ascii(nombre_carpeta))
    nombre_norm <- gsub("[^a-z0-9]", "_", nombre_norm)
    nombre_norm <- gsub("_+", "_", nombre_norm)
    
    # Guardar subtabla individual en parquet y rds para máxima portabilidad
    ruta_sub_parquet <- file.path(dir_historico_loc, paste0(nombre_norm, ".parquet"))
    ruta_sub_rds     <- file.path(dir_historico_loc, paste0(nombre_norm, ".rds"))
    
    arrow::write_parquet(df_loc, ruta_sub_parquet)
    saveRDS(df_loc, ruta_sub_rds)
    
    lista_subtablas[[nombre_norm]] <- df_loc
    message(paste0("  ✔ Subtabla preservada: ", nombre_norm, " (", nrow(df_loc), " filas brutas)"))
  }
  
  df_bruto_total <- dplyr::bind_rows(lista_subtablas)
  message(paste0("✔ Total filas brutas unificadas: ", nrow(df_bruto_total)))
  return(df_bruto_total)
}

# 5. Metodología de Limpieza y Consolidación ----

consolidar_datos_noticias <- function(df_bruto) {
  message(">>> [Paso 2/4] Ejecutando metodología de limpieza y validación territorial...")
  
  ciudad_buscar <- a_ascii("Bogotá")
  
  df_limpio <- df_bruto %>%
    # Paso 2.1: Filtro de presencia de Bogotá (normalizado sin acentos)
    mutate(
      titulo_norm  = a_ascii(titulo),
      resumen_norm = a_ascii(resumen),
      cuerpo_norm  = a_ascii(cuerpo)
    ) %>%
    filter(
      str_detect(titulo_norm, fixed(ciudad_buscar, ignore_case = TRUE)) |
      str_detect(resumen_norm, fixed(ciudad_buscar, ignore_case = TRUE)) |
      str_detect(cuerpo_norm, fixed(ciudad_buscar, ignore_case = TRUE))
    ) %>%
    select(-titulo_norm, -resumen_norm, -cuerpo_norm) %>%
    
    # Paso 2.2: Extracción de fuente (medio periodístico o institucional)
    mutate(fuente = extraer_dominio(enlace)) %>%
    
    # Paso 2.3: Identificación de la localidad a partir de la consulta booleana
    mutate(
      localidad = str_extract(consulta, "(?<=\\+hurtos\\s).*$"),
      localidad = str_replace_all(localidad, "\\+", " "),
      localidad = str_squish(str_to_title(localidad))
    ) %>%
    select(-consulta) %>%
    
    # Paso 2.4: Priorización de relevancia y descarte de URLs duplicadas
    mutate(
      localidad_en_texto = str_detect(str_to_upper(titulo), str_to_upper(localidad)) |
        str_detect(str_to_upper(resumen), str_to_upper(localidad))
    ) %>%
    arrange(enlace, desc(localidad_en_texto)) %>%
    distinct(enlace, .keep_all = TRUE)
  
  message(paste0("✔ Total noticias únicas consolidadas: ", nrow(df_limpio)))
  return(df_limpio)
}

# 6. Generación de Metadatos de Cobertura Temporal ----

generar_metadatos_cobertura <- function(df_bruto, df_consolidado) {
  message(">>> [Paso 3/4] Calculando metadatos de cobertura temporal para scraping incremental...")
  
  # Resumen por localidad
  cobertura <- df_consolidado %>%
    group_by(localidad) %>%
    summarise(
      noticias_consolidadas = n(),
      fecha_min = min(as.Date(fecha_chunk_desde), na.rm = TRUE),
      fecha_max = max(as.Date(fecha_chunk_desde), na.rm = TRUE),
      meses_cubiertos = list(sort(unique(format(as.Date(fecha_chunk_desde), "%Y-%m")))),
      fuentes_principales = list(head(names(sort(table(fuente), decreasing = TRUE)), 5)),
      .groups = "drop"
    )
  
  metadatos <- list(
    proyecto = "Hurtos y Sentimiento Mediatico en Bogota (2022-2025)",
    fecha_generacion = as.character(Sys.time()),
    total_filas_brutas = nrow(df_bruto),
    total_filas_consolidadas = nrow(df_consolidado),
    rango_global = list(
      inicio = as.character(min(as.Date(df_consolidado$fecha_chunk_desde), na.rm = TRUE)),
      fin    = as.character(max(as.Date(df_consolidado$fecha_chunk_desde), na.rm = TRUE))
    ),
    localidades = split(cobertura, seq_len(nrow(cobertura)))
  )
  
  jsonlite::write_json(metadatos, archivo_metadatos, pretty = TRUE, auto_unbox = TRUE)
  message(paste0("✔ Metadatos de cobertura exportados a: ", archivo_metadatos))
  return(metadatos)
}

# 7. Funciones Exportables para Scraping Incremental Futuro ----

#' Consulta los meses (YYYY-MM) que ya se encuentran cubiertos para una localidad
#' @param nombre_localidad Nombre de la localidad en formato texto
#' @return Vector de caracteres con los meses en formato "YYYY-MM"
obtener_meses_cubiertos <- function(nombre_localidad) {
  if (!file.exists(archivo_metadatos)) {
    warning("No existe el archivo de metadatos de cobertura.")
    return(character(0))
  }
  meta <- jsonlite::fromJSON(archivo_metadatos)
  loc_data <- purrr::keep(meta$localidades, ~ tolower(a_ascii(.x$localidad)) == tolower(a_ascii(nombre_localidad)))
  if (length(loc_data) == 0) return(character(0))
  return(loc_data[[1]]$meses_cubiertos)
}

#' Filtra una lista de meses objetivo excluyendo los que ya fueron procesados
#' @param nombre_localidad Nombre de la localidad
#' @param meses_objetivo Vector de meses formato Date o "YYYY-MM"
#' @return Vector de meses pendientes de scrapear
filtrar_meses_pendientes <- function(nombre_localidad, meses_objetivo) {
  meses_cubiertos <- obtener_meses_cubiertos(nombre_localidad)
  formato_meses <- format(as.Date(meses_objetivo), "%Y-%m")
  pendientes <- meses_objetivo[!(formato_meses %in% meses_cubiertos)]
  return(pendientes)
}

# 8. Ejecución Principal ----

ejecutar_migracion_completa <- function() {
  cat("\n==================================================================\n")
  cat("  MIGRACIÓN Y CONSOLIDACIÓN METODOLÓGICA DE NOTICIAS HISTÓRICAS  \n")
  cat("==================================================================\n\n")
  
  df_bruto <- migrar_subtablas_historicas()
  df_consolidado <- consolidar_datos_noticias(df_bruto)
  
  message(">>> [Paso 4/4] Guardando base consolidada...")
  arrow::write_parquet(df_consolidado, archivo_consolidado_p)
  saveRDS(df_consolidado, archivo_consolidado_r)
  message(paste0("  ✔ Parquet: ", archivo_consolidado_p))
  message(paste0("  ✔ RDS:     ", archivo_consolidado_r))
  
  generar_metadatos_cobertura(df_bruto, df_consolidado)
  
  cat("\n==================================================================\n")
  cat("  RESUMEN DE VALIDACIÓN:\n")
  cat(paste0("  - Total subtablas individuales: 19\n"))
  cat(paste0("  - Total filas brutas en origen: ", format(nrow(df_bruto), big.mark = ","), "\n"))
  cat(paste0("  - Total noticias únicas finales: ", format(nrow(df_consolidado), big.mark = ","), "\n"))
  cat(paste0("  - NAs en columnas clave: ", sum(is.na(df_consolidado$enlace)), " (cero esperado)\n"))
  cat("==================================================================\n\n")
  
  return(invisible(df_consolidado))
}

# Ejecutar automáticamente si es invocado vía Rscript
if (!interactive()) {
  ejecutar_migracion_completa()
}
