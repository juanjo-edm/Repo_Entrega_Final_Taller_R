# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ROL: Batería de Pruebas Unitarias y de Integración para el Scraper de Noticias
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración de Entorno de Pruebas ----
suppressPackageStartupMessages({
  library(here)
  library(arrow)
  library(dplyr)
  library(stringr)
})

# Desactivar auto-ejecución para cargar únicamente las funciones en el entorno de pruebas
auto_ejecutar <- FALSE
source(here::here("scripts", "01_ingesta", "02_scraping_noticias", "scraping_google_news.R"))

cat("\n==================================================================\n")
cat("🧪 INICIANDO BATERÍA DE PRUEBAS DEL SCRAPER DE GOOGLE NEWS\n")
cat("==================================================================\n\n")

total_pruebas  <- 0
pruebas_exito  <- 0

afirmar <- function(descripcion, condicion) {
  total_pruebas <<- total_pruebas + 1
  if (isTRUE(condicion)) {
    pruebas_exito <<- pruebas_exito + 1
    cat(paste0("  ✔ [PASÓ] ", descripcion, "\n"))
  } else {
    cat(paste0("  ❌ [FALLÓ] ", descripcion, "\n"))
  }
}

# 2. Prueba 1: Constructor de Consultas Booleanas ----
cat(">>> Test 1: Validación de sintaxis en consultas booleanas...\n")

q_kennedy    <- construir_consulta_rss("KENNEDY")
q_santafe    <- construir_consulta_rss("SANTA FE")
q_candelaria <- construir_consulta_rss("LA CANDELARIA")

afirmar("Kennedy contiene sinónimos de delitos y comillas de localidad", 
        str_detect(q_kennedy, 'hurto') && str_detect(q_kennedy, '"Kennedy"') && str_detect(q_kennedy, 'Bogota'))

afirmar("Santa Fe excluye términos de fútbol (liga, campin, dimayor)", 
        str_detect(q_santafe, '-futbol') && str_detect(q_santafe, '-liga') && str_detect(q_santafe, '-campin'))

afirmar("No se incluye la palabra restrictiva 'localidad'", 
        !str_detect(q_kennedy, 'localidad') && !str_detect(q_candelaria, 'localidad'))

# 3. Prueba 2: Generación de URLs de Google News RSS ----
cat("\n>>> Test 2: Construcción de URLs de Google News RSS...\n")

url_test <- build_google_news_url("hurto Bogota Kennedy")

afirmar("URL contiene endpoint oficial de Google News RSS", str_detect(url_test, "news.google.com/rss/search"))
afirmar("URL contiene parámetro de consulta q codificada", str_detect(url_test, "q=hurto"))
afirmar("URL contiene parámetros de idioma y región", str_detect(url_test, "hl=es-419") && str_detect(url_test, "gl=CO"))

# 4. Prueba 3: Limpieza y Normalización de Enlaces ----
cat("\n>>> Test 3: Limpieza y normalización de URLs...\n")

url_con_utm   <- "https://www.eltiempo.com/bogota/robo-kennedy-123?utm_source=twitter&utm_medium=social"
url_google_q  <- "/url?q=https://www.elespectador.com/bogota/atraco-456&sa=U&ved=2ahU"
url_vacia     <- ""

afirmar("Remueve parámetros UTM de analítica", 
        limpiar_enlace(url_con_utm) == "https://www.eltiempo.com/bogota/robo-kennedy-123")

afirmar("Decodifica redirector interno de Google /url?q=", 
        str_detect(limpiar_enlace(url_google_q), "https://www.elespectador.com"))

afirmar("Maneja URLs vacías o NAs retornando NA", is.na(limpiar_enlace(url_vacia)))

# 5. Prueba 4: Extracción de Cuerpo con Fallback Resiliente ----
cat("\n>>> Test 4: Extracción de cuerpo con fallback...\n")

fallback_texto <- "Texto breve del resumen que debe mantenerse ante fallas"
resultado_fb   <- extraer_cuerpo_noticia("https://url-inexistente-123456789.com/nota", fallback_texto)

afirmar("Retorna el resumen fallback si la URL no responde o es inválida", resultado_fb == fallback_texto)

# 6. Prueba 5: Integridad de la Base de Datos Consolidada ----
cat("\n>>> Test 5: Auditoría de integridad de datos consolidados...\n")

archivo_parquet <- here::here("data", "raw", "noticias_google_news_consolidado.parquet")
afirmar("El archivo consolidado parquet existe en data/raw/", file.exists(archivo_parquet))

if (file.exists(archivo_parquet)) {
  df_check <- arrow::read_parquet(archivo_parquet)
  
  afirmar("La base consolidada contiene al menos 2.487 noticias", nrow(df_check) >= 2487)
  afirmar("Cero valores nulos (NA) en enlaces", sum(is.na(df_check$enlace)) == 0)
  afirmar("Cero valores nulos (NA) en títulos", sum(is.na(df_check$titulo)) == 0)
  afirmar("Contiene representación de las 19 localidades", length(unique(df_check$localidad)) >= 19)
}

# 7. Resumen Final de Pruebas ----
cat("\n==================================================================\n")
cat(paste0("📋 RESULTADO FINAL: ", pruebas_exito, " de ", total_pruebas, " pruebas superadas con éxito.\n"))
if (pruebas_exito == total_pruebas) {
  cat("✔ Todas las pruebas unitarias y de integración pasaron satisfactoriamente.\n")
} else {
  cat("⚠ Se encontraron fallos en algunas pruebas. Revisar detalles arriba.\n")
}
cat("==================================================================\n\n")
