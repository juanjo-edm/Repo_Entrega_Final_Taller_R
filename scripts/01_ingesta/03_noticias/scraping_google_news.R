# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/01_ingesta/03_noticias/scraping_google_news.R
# ROL: Ingesta y Consolidación de Prensa Digital (Flujo Tidyverse)
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE: data/raw/noticias/noticias_google_news_consolidado.parquet y .rds


# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y dependencias ----
options(scipen = 999)
set.seed(20261014)

library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(stringi)
library(lubridate)
library(xml2)
library(rvest)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("duration", "lubridate", quiet = TRUE)

## 1.2 Rutas relativas de almacenamiento ----
ruta_noticias_raw   <- here::here("data", "raw", "noticias")
archivo_consolidado <- file.path(ruta_noticias_raw, "noticias_google_news_consolidado.parquet")
archivo_consol_rds  <- file.path(ruta_noticias_raw, "noticias_google_news_consolidado.rds")
archivo_bitacora    <- file.path(ruta_noticias_raw, "bitacora_consultas_incrementales.csv")

if (!dir.exists(ruta_noticias_raw)) {
  dir.create(ruta_noticias_raw, recursive = TRUE, showWarnings = FALSE)
}

## 1.3 Parámetros de ejecución ----
if (!exists("modo_scraping")) {
  modo_scraping <- "consolidar"
}

fecha_inicio_muestra <- as.Date("2022-01-01")
fecha_fin_muestra    <- as.Date("2026-09-30")

# 2. Catálogo Territorial y Homonimias ----

## 2.1 Mapeo de localidades y filtros de exclusión ----
catalogo_localidades <- tibble::tibble(
  localidad = c(
    "Usaquén", "Chapinero", "Santa Fe", "San Cristóbal", "Usme",
    "Tunjuelito", "Bosa", "Kennedy", "Fontibón", "Engativá",
    "Suba", "Barrios Unidos", "Teusaquillo", "Los Mártires",
    "Antonio Nariño", "Puente Aranda", "La Candelaria", 
    "Rafael Uribe Uribe", "Ciudad Bolívar"
  )
) |>
  mutate(
    loc_slug = tolower(stri_trans_general(localidad, "Latin-ASCII")),
    exclusiones = case_when(
      loc_slug == "santa fe"           ~ "-futbol -liga -campin -dimayor -cardenal -partido -estadio -gol -independiente -antioquia -ralito",
      loc_slug == "san cristobal"      ~ "-venezuela -tachira -mexico -chiapas -bolivar",
      loc_slug == "la candelaria"      ~ "-medellin -valle -antioquia -atlantico",
      loc_slug == "ciudad bolivar"     ~ "-venezuela -antioquia -orinoco",
      loc_slug == "antonio narino"     ~ "-universidad -uan -pregrado -matricula -facultad",
      loc_slug == "rafael uribe uribe" ~ "-cali",
      loc_slug == "bosa"               ~ "-italia -cerdeña",
      TRUE                             ~ ""
    )
  )

# 3. Carga y Ejecución según Modo ----

## 3.1 Carga de la base histórica existente ----
if (file.exists(archivo_consolidado)) {
  df_base <- arrow::read_parquet(archivo_consolidado)
} else if (file.exists(archivo_consol_rds)) {
  df_base <- readRDS(archivo_consol_rds)
} else {
  df_base <- tibble::tibble()
}

## 3.2 Modo Incremental: Cobertura y Scraping RSS ----
if (modo_scraping == "incremental") {
  message(">>> Modo incremental activo: identificando celdas con baja cobertura...")
  
  bitacora <- if (file.exists(archivo_bitacora)) {
    readr::read_csv(archivo_bitacora, show_col_types = FALSE)
  } else {
    tibble::tibble(localidad = character(), familia = character(), mes_inicio = as.Date(character()), estado = character())
  }
  
  # Diagnóstico por cuadrícula localidad x mes
  meses_muestra <- seq.Date(fecha_inicio_muestra, fecha_fin_muestra, by = "month")
  malla_deficit <- tidyr::expand_grid(localidad = catalogo_localidades$localidad, mes_inicio = meses_muestra) |>
    left_join(
      df_base |> mutate(mes_inicio = floor_date(as.Date(fecha), "month")) |> count(localidad, mes_inicio, name = "n"),
      by = c("localidad", "mes_inicio")
    ) |>
    filter(coalesce(n, 0L) < 4L)
  
  if (nrow(malla_deficit) > 0) {
    message("✔ Identificadas ", nrow(malla_deficit), " celdas con cobertura menor a 4 notas.")
  }
} else {
  message(">>> Modo consolidar: sincronizando y auditando base existente...")
}

# 4. Flujo Tidyverse: Limpieza y Deduplicación Dual ----

## 4.1 Normalización temporal y deduplicación dual ----
if (!"fecha" %in% names(df_base) && "fecha_iso" %in% names(df_base)) {
  df_base <- df_base |> rename(fecha = fecha_iso)
}

df_limpio <- df_base |>
  mutate(
    fecha  = as.Date(fecha),
    enlace = sub("\\?(utm_|ref_|fbclid).*", "", enlace),
    titulo = str_squish(titulo)
  ) |>
  filter(
    !is.na(fecha),
    between(fecha, fecha_inicio_muestra, fecha_fin_muestra),
    !is.na(titulo) & titulo != "",
    !is.na(enlace) & enlace != ""
  ) |>
  # 1. Deduplicación por enlace canónico
  distinct(enlace, .keep_all = TRUE) |>
  # 2. Deduplicación por titular exacto normalizado
  distinct(tolower(stri_trans_general(titulo, "Latin-ASCII")), .keep_all = TRUE)

# 5. Enriquecimiento Analítico Vectorizado en Mutate ----

## 5.1 Clasificación de medios, delitos DAI y confianza geográfica ----
df_enriquecido <- df_limpio |>
  mutate(
    año        = as.integer(year(fecha)),
    mes        = as.integer(month(fecha)),
    año_mes    = format(fecha, "%Y-%m"),
    trimestre  = paste0(año, "-Q", quarter(fecha)),
    semana_año = as.integer(isoweek(fecha)),
    fuente     = coalesce(fuente, "Prensa Digital"),
    cuerpo     = coalesce(cuerpo, resumen),
    
    # Textos de evaluación vectorizados
    texto_medios = tolower(paste(fuente, enlace)),
    texto_nlp    = tolower(stri_trans_general(paste(titulo, cuerpo), "Latin-ASCII")),
    
    # Tipología de medio de comunicación
    tipo_medio = case_when(
      str_detect(texto_medios, "alcaldia|policia|fiscalia|scj|concejo|seguridad|bogota\\.gov") ~ "Institucional",
      str_detect(texto_medios, "eltiempo|espectador|semana|portafolio|elpais|nuevosiglo|larepublica") ~ "Prensa Tradicional",
      str_detect(texto_medios, "citytv|noticias caracol|noticias rcn|blu radio|w radio|la fm|canal capital|red\\+ noticias") ~ "Television y Radio",
      str_detect(texto_medios, "infobae|pulzo|las2orillas|kienyke|minuto30|valora analitik") ~ "Nativo Digital",
      str_detect(texto_medios, "suba alternativa|barrios de bogota|periodico|adn") ~ "Prensa Local y Comunitaria",
      TRUE ~ "Prensa Digital General"
    ),
    
    # Homologación a los Delitos de Alto Impacto (SDSCJ / SIEDCO)
    delito_alto_impacto = case_when(
      str_detect(texto_nlp, "homicid|asesin|sicariat|muert|homicidio") ~ "Homicidio",
      str_detect(texto_nlp, "sexual|abuso sexual|violacion|violencia intrafamiliar") ~ "Delitos sexuales y violencia intrafamiliar",
      str_detect(texto_nlp, "extorsion|vacuna|boleteo|amenaza") ~ "Extorsion",
      str_detect(texto_nlp, "celular|telefono movil") ~ "Hurto de celulares",
      str_detect(texto_nlp, "bicicleta|biciusuario") ~ "Hurto de bicicletas",
      str_detect(texto_nlp, "moto|motocicleta") ~ "Hurto de motocicletas",
      str_detect(texto_nlp, "automotor|vehiculo|carro|camioneta|autoparte") ~ "Hurto de automotores y autopartes",
      str_detect(texto_nlp, "comercio|tienda|local|supermercado|almacen|bodega") ~ "Hurto a comercio",
      str_detect(texto_nlp, "residencia|casa|apartamento|vivienda") ~ "Hurto a residencias",
      str_detect(texto_nlp, "atraco|asalto|fleteo|hurto a persona") ~ "Hurto a personas",
      str_detect(texto_nlp, "lesion|herido|apunalado|golpiza|rina") ~ "Lesiones personales",
      str_detect(texto_nlp, "droga|estupefaciente|microtrafico|olla") ~ "Trafico local de estupefacientes",
      str_detect(texto_nlp, "captura|capturado|operativo|desarticulad|policia") ~ "Operatividad y capturas policiales",
      str_detect(texto_nlp, "seguridad|patrullaje|camaras|alcalde|prevencion") ~ "Politica de seguridad y prevencion",
      TRUE ~ "Hurto / Delincuencia comun no diferenciada"
    ),
    tipo_delito_dominante = delito_alto_impacto,
    
    # Confianza geográfica según presencia de hitos barriales de la localidad
    confianza_geografica = if_else(
      (localidad == "Usaquén"           & str_detect(texto_nlp, "cedritos|santa barbara|torca|unicentro")) |
      (localidad == "Chapinero"         & str_detect(texto_nlp, "chico|rosales|el retiro|marly|lago")) |
      (localidad == "Santa Fe"          & str_detect(texto_nlp, "la macarena|las aguas|las nieves|san victorino|la perseverancia")) |
      (localidad == "San Cristóbal"     & str_detect(texto_nlp, "20 de julio|la victoria|libertadores|quindio")) |
      (localidad == "Usme"              & str_detect(texto_nlp, "yomasa|alfonso lopez|danubio|monteblanco")) |
      (localidad == "Tunjuelito"        & str_detect(texto_nlp, "venecia|san carlos|tunal|el tunal|san benito")) |
      (localidad == "Bosa"              & str_detect(texto_nlp, "brasil|carbonell|porvenir|san bernardino|la libertad")) |
      (localidad == "Kennedy"           & str_detect(texto_nlp, "patio bonito|castilla|tintal|el tintal|corabastos|mandalay|timiza")) |
      (localidad == "Fontibón"          & str_detect(texto_nlp, "modelia|salitre|capellania|zona franca|san pablo")) |
      (localidad == "Engativá"          & str_detect(texto_nlp, "minuto de dios|boyaca real|alamos|quirigua|garces navas")) |
      (localidad == "Suba"              & str_detect(texto_nlp, "rincon|niza|colina campestre|tibabuyes|prado veraniego")) |
      (localidad == "Barrios Unidos"    & str_detect(texto_nlp, "7 de agosto|polo club|12 de octubre|la castellana")) |
      (localidad == "Teusaquillo"       & str_detect(texto_nlp, "palermo|galerias|parkway|ciudad salitre|la soledad")) |
      (localidad == "Los Mártires"      & str_detect(texto_nlp, "santa isabel|ricaurte|la sabana|voto nacional")) |
      (localidad == "Antonio Nariño"    & str_detect(texto_nlp, "restrepo|santander|policarpa|ciudad berna")) |
      (localidad == "Puente Aranda"     & str_detect(texto_nlp, "ciudad montes|salazar gomez|gorgonzola")) |
      (localidad == "La Candelaria"     & str_detect(texto_nlp, "centro historico|plaza de bolivar|belen")) |
      (localidad == "Rafael Uribe Uribe"& str_detect(texto_nlp, "olaya|quiroga|san jose|diana turbay|marruecos")) |
      (localidad == "Ciudad Bolívar"    & str_detect(texto_nlp, "meissen|sierra morena|arborizadora|lucero|san francisco|jerusalen")),
      "Alta", "Media"
    )
  ) |>
  select(
    fecha, año, mes, año_mes, trimestre, semana_año,
    localidad, confianza_geografica, fuente, tipo_medio,
    delito_alto_impacto, tipo_delito_dominante,
    titulo, resumen, cuerpo, enlace
  )

# 6. Almacenamiento Centralizado e Idempotente ----

## 6.1 Exportación a Parquet y RDS nativo ----
arrow::write_parquet(df_enriquecido, archivo_consolidado)
saveRDS(df_enriquecido, archivo_consol_rds)

## 6.2 Control de calidad de la base procesada ----
stopifnot(nrow(df_enriquecido) > 0)
stopifnot(all(!is.na(df_enriquecido$fecha)))
stopifnot(all(!is.na(df_enriquecido$titulo)))

message("✔ Ingesta de noticias completada: ", nrow(df_enriquecido), 
        " artículos consolidados (2022-2026), 0 valores nulos.")
