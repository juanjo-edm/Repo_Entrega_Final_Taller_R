# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/02_procesamiento/03_noticias/procesamiento_noticias.R
# ROL: Consolidación rectangular y slugs sin guiones (T-05), limpieza de texto NLP
#      y remoción de HTML sin NAs (T-06), extracción de métricas y reclasificación
#      oficial de Delitos de Alto Impacto (DAI) de la SDSCJ
# AUTORES: Sergio López, Gabriel Arturo Echeverry, Juan José Echeverry, Miguelangel Palma
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ENTRA: data/raw/noticias/noticias_google_news_consolidado.parquet
# PRODUCE: data/processed/03_noticias/noticias_procesadas.parquet
#          output/tables/tabla_reclasificacion_dai.csv
#          output/tables/tabla_conteo_localidad_anio_dai.csv
#          output/tables/muestra_validacion_manual_dai.csv
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Librerías necesarias ----
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(stringi)
library(lubridate)

## 1.3 Resolución explícita de conflictos ----
conflict_prefer("filter",  "dplyr", quiet = TRUE)
conflict_prefer("lag",     "dplyr", quiet = TRUE)
conflict_prefer("select",  "dplyr", quiet = TRUE)
conflict_prefer("quarter", "lubridate", quiet = TRUE)

## 1.4 Rutas de entrada, procesamiento y reportes ----
ruta_entrada_raw     <- here("data", "raw", "noticias", "noticias_google_news_consolidado.parquet")
ruta_salida_proc_dir <- here("data", "processed", "03_noticias")
ruta_salida_tablas   <- here("output", "tables")

if (!dir.exists(ruta_salida_proc_dir)) dir.create(ruta_salida_proc_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(ruta_salida_tablas))   dir.create(ruta_salida_tablas, recursive = TRUE, showWarnings = FALSE)

# 2. Carga y Normalización Territorial y Temporal ----

## 2.1 Lectura de noticias consolidadas y generación de slugs sin guiones ----
# sentometrics usa '--' para separar léxico, feature y tiempo; normalizamos
# cada localidad a snake_case sin tildes ni guiones para evitar rupturas.
df_crudo <- read_parquet(ruta_entrada_raw) |>
  as_tibble() |>
  mutate(
    localidad_slug = localidad |>
      stri_trans_general("Latin-ASCII") |>
      str_to_lower() |>
      str_remove("^la\\s+") |>
      str_replace_all("[\\s\\-]+", "_")
  )

## 2.2 Unificación de fechas canónicas (Date yyyy-mm-dd) ----
# Garantizamos una columna 'fecha' tipo Date (usando fecha_iso o el inicio del
# bloque de búsqueda como respaldo) y derivamos año, mes, trimestre y semana
# para alinear el corpus con las series mensuales y el panel anual de delitos.
if (!"fecha" %in% colnames(df_crudo)) {
  df_crudo <- df_crudo |>
    mutate(
      fecha = if ("fecha_iso" %in% colnames(df_crudo)) {
        if_else(!is.na(fecha_iso) & fecha_iso != "", as.Date(fecha_iso), as.Date(fecha_chunk_desde))
      } else {
        as.Date(fecha_chunk_desde)
      }
    )
} else {
  df_crudo <- df_crudo |> mutate(fecha = as.Date(fecha))
}

df_crudo <- df_crudo |>
  mutate(
    año        = as.integer(coalesce(año, as.integer(format(fecha, "%Y")))),
    mes        = as.integer(coalesce(mes, as.integer(format(fecha, "%m")))),
    año_mes    = coalesce(año_mes, format(fecha, "%Y-%m")),
    trimestre  = coalesce(trimestre, paste0(año, "-T", quarter(fecha))),
    semana_año = coalesce(semana_año, as.integer(format(fecha, "%V")))
  )

# 3. Limpieza de Texto, Remoción de HTML y Métricas NLP ----

## 3.1 Depuración de ruido web, paywalls y etiquetas HTML ----
# Cuando el scraping captura muros de suscripción, avisos de cookies o cuerpos
# casi vacíos, usamos el resumen como respaldo para no perder el registro ni
# contaminar los léxicos de sentimiento con texto de interfaz web.
limpiar_cuerpo_web <- function(cuerpo, resumen) {
  es_ruido_portal <- str_detect(
    cuerpo,
    "Consulta aquí la información que te interesa sobre Bogotá|Publicidad Publicidad Publicidad|Puntos de venta Suscribirse a El Nuevo Siglo"
  ) | (grepl("cookies", cuerpo, ignore.case = TRUE) & nchar(cuerpo) < 500)

  texto <- if_else(es_ruido_portal, resumen, cuerpo)

  patrones_ruido <- c(
    "<[^>]+>",
    "&nbsp;|&#160;|&quot;|&amp;|&lt;|&gt;|&#[0-9]+;",
    "(?i)[^\n.]*\\bcookies\\b[^\n.]*\\.?",
    "¿Cómo podemos ayudarte\\?.*",
    "Audio generado con IA de Google [0-9]+:[0-9]+ / [0-9]+:[0-9]+",
    "¡Comparte\\s+esta nota!.*",
    "COPYRIGHT ©.*",
    "(?i)(lea también|lea además|le puede interesar|vea también|siga leyendo|noticia en desarrollo)[^.]*\\.",
    "(?i)(foto|crédito|video):\\s*[^.]*(\\.|\\n|$)",
    "\\bPublicidad\\b",
    "https?://\\S+|www\\.\\S+",
    "[\r\n\t\u00a0]+"
  )

  texto <- reduce(patrones_ruido, ~ gsub(.y, " ", .x, perl = TRUE), .init = texto) |>
    str_squish()

  # Si tras limpiar queda muy poco contenido útil, recurrimos al resumen depurado
  texto <- if_else(nchar(texto) < 40 | is.na(texto), resumen, texto)
  str_squish(gsub("<[^>]+>", " ", texto))
}

cuerpo_original <- df_crudo$cuerpo
cuerpo_depurado <- limpiar_cuerpo_web(cuerpo_original, df_crudo$resumen)

## 3.2 Métricas de volumen léxico y texto unificado ----
# Limpiamos etiquetas residuales en el titular, calculamos conteos de extensión
# para los diagnósticos descriptivos del corpus y concatenamos título y cuerpo
# en 'texto_completo_nlp' como insumo limpio para el análisis de sentimiento.
df_limpio <- df_crudo |>
  mutate(
    titulo             = str_squish(gsub("<[^>]+>", " ", titulo)),
    cuerpo             = cuerpo_depurado,
    caracteres_cuerpo  = nchar(cuerpo),
    palabras_cuerpo    = str_count(cuerpo, "\\S+"),
    palabras_titulo    = str_count(titulo, "\\S+"),
    texto_completo_nlp = str_squish(paste(titulo, ".", cuerpo))
  )

# 4. Clasificación Oficial DAI de la SDSCJ ----
# Taxonomía oficial de 11 Delitos de Alto Impacto (DAI) monitoreados por la
# Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ) a partir de
# registros SIEDCO (Policía Nacional) — Datos Abiertos Bogotá:
# https://datosabiertos.bogota.gov.co/dataset/delito-de-alto-impacto-bogota-d-c
# (Homicidio, Lesiones personales, Hurto a personas, residencias, comercio,
#  entidades financieras, automotores, motocicletas, Extorsión, Delitos
#  sexuales y Violencia intrafamiliar).

## 4.1 Normalización léxica para matching ----
# Quitamos tildes, puntuación y mayúsculas para que las reglas regex operen de
# forma uniforme. Limitamos el cuerpo a 1.500 caracteres porque los primeros
# párrafos concentran el hecho central y evitan menciones de casos pasados.
normalizar_texto <- function(x) {
  x |>
    stri_trans_general("Latin-ASCII") |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9 ]", " ") |>
    str_squish()
}

df_clasif <- df_limpio |>
  mutate(
    txt_titulo  = normalizar_texto(titulo),
    txt_resumen = normalizar_texto(resumen),
    txt_cuerpo  = normalizar_texto(str_sub(cuerpo, 1, 1500))
  )

## 4.2 Diccionarios y patrones con límites de palabra ----
# Verbos y sustantivos asociados a hurto (excluyendo falsos amigos como "robot"
# o "robusto") para detectar el tipo de delito por proximidad sintáctica.
verbo_hurto <- paste0(
  "(hurt\\w*|rob(?!(ust|ot|ert|led|ins|le\\b|les\\b))\\w*|atraco|atracos|atraca|atracan|atracaron|",
  "atracado|atracada|atracador\\w*|asalto|asaltos|asaltan|asaltaron|asaltado\\w*|",
  "asaltante\\w*|saque\\w*|desvalij\\w*|escopolamin\\w*|rompevidrios|raponaz\\w*|raponer\\w*|cosquille\\w*|fleteo\\w*|fletero\\w*|",
  "ladron|ladrones|ladrona\\w*|apartamenter\\w*|robacarros|robamotos|halado\\w*)"
)
patron_hurto <- paste0("\\b", verbo_hurto, "\\b")

objetos_hurto <- list(
  hurto_entidades_financieras = "(bancos?|entidad(es)? financieras?|sucursal(es)? bancarias?|oficinas? bancarias?|cajeros? (automaticos?|electronicos?)|corresponsal(es)? bancarios?)",
  hurto_automotores           = "(vehiculos?|carros?|automoviles?|automotor(es)?|camionetas?|camion(es)?|taxis?|campero|tractomulas?|autopartes|espejos?|llantas|rines)",
  hurto_motocicletas          = "(motos?|motocicletas?)",
  hurto_bicicletas            = "(bicicletas?|bicis?)",
  hurto_celulares             = "(celular(es)?|telefonos? (moviles?|celulares?)|iphones?|smartphones?|equipos? moviles?)",
  hurto_residencias           = "(residencias?|viviendas?|apartamentos?|casas?(?! de (empeno|cambio|apuestas))|hogar(es)?|conjuntos? residencial(es)?|edificios? residencial(es)?)",
  hurto_comercio              = "(comercios?|establecimientos?( comerciales?)?|locales?( comerciales?)?|negocios?|tiendas?|supermercados?|almacen(es)?|droguerias?|farmacias?|joyerias?|panaderias?|restaurantes?|minimercados?|ferreterias?|centros? comerciales?|comerciantes?|bodegas?|cigarrerias?|licoreras?|discotecas?|estaciones? de servicio|gasolineras?|casas? de empeno|compraventas?|tenderos?|d1|oxxo|carnicerias?|cafeterias?|inmobiliarias?|peluquerias?|cajeras?)",
  hurto_personas              = "(personas?|ciudadanos?|transeuntes?|peatones?|pasajeros?|usuarios?|estudiantes?|mujer(es)?|hombres?|jovenes|joven|adultos? mayor(es)?|abuelos?|turistas?|conductor(es)?|repartidor(es)?|domiciliarios?|ninos?|ninas?|menor(es)?|transmilenio|sitp|paradero|bus(es)?|billeteras?|bolsos?|joyas?|cadenas?|relojes?|reloj|morral(es)?|mochilas?)"
)

participio_hurto <- "(robad[oa]s?|hurtad[oa]s?|saquead[oa]s?|desvalijad[oa]s?)"

# Exige cercanía de 0 a 4 palabras tras el verbo (o 0 a 3 antes del participio)
# para evitar falsos positivos cuando "hurto" y el objeto aparecen en frases distintas.
construir_patron_objeto <- function(objeto) {
  paste0(
    "\\b", verbo_hurto, "\\b(\\s+\\w+){0,4}\\s+\\b", objeto, "\\b|",
    "\\b", objeto, "\\b(\\s+\\w+){0,3}\\s+\\b", participio_hurto, "\\b"
  )
}
patrones_objeto <- lapply(objetos_hurto, construir_patron_objeto)

# Expresiones inequívocas de modalidades de hurto en el contexto bogotano
patrones_directos <- list(
  hurto_personas     = "\\b(hurto a personas|robo a personas|atracos?|escopolamin\\w*|raponaz\\w*|cosquille\\w*|fleteo\\w*|fleteros?|paseo millonario|escopolamina|burundanga)\\b",
  hurto_residencias  = "\\b(hurto a residencias|robo a residencias|apartamenteros?|hurto a viviendas?)\\b",
  hurto_comercio     = "\\b(hurto a comercio|robo a comercio|hurto a establecimientos?)\\b",
  hurto_automotores  = "\\b(hurto de (automotores|vehiculos|carros)|rompevidrios|robacarros|halado de vehiculos?|desguazadero\\w*|deshuesadero\\w*|recuper\\w*( \\w+){0,3} (vehiculos?|carros?|camion(es)?|camionetas?|automotor(es)?|automoviles?))\\b",
  hurto_motocicletas = "\\b(hurto de motocicletas|robamotos|halado de motos?|(desguazadero|deshuesadero)s? de motos|recuper\\w*( \\w+){0,3} (motos?|motocicletas?))\\b"
)

contexto_comercio <- paste0("\\b", objetos_hurto$hurto_comercio, "\\b")
contexto_personas <- paste0(
  "\\b(pasajeros?|transmilenio|sitp|paraderos?|transeuntes?|peatones?|via publica|",
  "en (plena )?(via|calle)|relojes?|reloj|cadenas?|joyas?|billeteras?|bolsos?|morral(es)?|mochilas?)\\b"
)

# Resto de Delitos de Alto Impacto (vida, integridad, libertad y patrimonio)
patron_homicidio <- paste0(
  "\\b(homicidi\\w*|asesin\\w*|sicari\\w*|feminicidi\\w*|mataron|matan a|mato a|",
  "lo mato|la mato|los mataron|le quitaron la vida|cuerpos? sin vida|cadaver(es)?|",
  "embolsad[oa]s?|ataque sicarial|muert[oa]s? (a tiros|a bala|a balazos|a punal\\w*|",
  "tras (un|una|el|la) (ataque|rina|atraco|robo|hurto|disparo)|por (un|una) (disparo|ataque|bala))|",
  "(dejo|deja|dejan|dejaron) (un|una|dos|tres|cuatro) muert[oa]s?|hallad[oa]s? muert[oa]s?|",
  "murio tras (ser|recibir)|crimen de (un|una))\\b"
)

patron_sexual <- paste0(
  "\\b(abusos? sexual(es)?|abusad[oa]s? sexualmente|acoso sexual|acosador(es)? sexual(es)?|",
  "violacion(es)?(?! (de|a) (la|los|las|derechos|medidas?|domicilio|normas?|protocolos?|privacidad))|",
  "violador(es)?|agresion(es)? sexual(es)?|acceso carnal|actos sexuales|delitos? sexual(es)?|",
  "explotacion sexual|pornografia infantil|tocamientos|abusador(es)?)\\b"
)

patron_vif <- paste0(
  "\\b(violencia intrafamiliar|violencia domestica|maltrato (intrafamiliar|infantil)|",
  "(agredio|golpeo|ataco|apunalo|maltrato|agrede|golpea) a su (pareja|esposa|esposo|companer[oa]|expareja|",
  "exnovi[oa]|novi[oa]|madre|mama|padre|papa|hij[oa]s?|bebe))\\b"
)

patron_extorsion <- paste0(
  "\\b(extorsi\\w*|extorsiv\\w*|cobro de vacunas?|vacunas? (a|contra|de) (comerciantes|tenderos|",
  "transportadores|conductores|negocios)|boleteo|pagar (la )?vacuna)\\b"
)

patron_lesiones <- paste0(
  "\\b(lesiones personales|lesionad[oa]s? (con|por|tras|a)|herid[oa]s? (con|por|de|tras|a) ",
  "(arma|bala|balazos?|cuchillo|punal|machete|navaja|disparos?|golpes)|apunal\\w*|punaladas?|",
  "acuchill\\w*|balead[oa]s?|golpiza\\w*|rinas?|agredid[oa]s? (con|a golpes)|",
  "ataque con (acido|arma blanca)|herida de bala|arma blanca|(atentado|ataque|disparos?|herid[oa]s?) a (bala|tiros|balazos)|",
  "agredir|agredio|agredieron|agredid[oa]s?|agrede|agreden)\\b"
)
# Siniestros viales y categorías de exclusión (infraestructura, microtráfico,
# operatividad policial y política pública) para separar noticias No DAI.
patron_transito <- "\\b(accidente\\w*|choque\\w*|siniestro vial|atropell\\w*|volcamiento|colision)\\b"

patron_otros_hurtos <- paste0(
  "\\b(cable\\w*|cobre|fibra optica|tapas( de alcantarill\\w*)?|alcantarill\\w*|medidor(es)?|contadores de (agua|gas|energia)|",
  "gas natural|hurto de (agua|energia|gas)|conexion(es)? ilegal(es)?|luminarias|infraestructura|semaforos?|mobiliario urbano|rejillas)\\b"
)
patron_microtrafico <- paste0(
  "\\b(estupefacientes|microtrafico|narcomenudeo|ollas?|expendio\\w*|jibaros?|bazuco|",
  "marihuana|cocaina|tusi|dosis|alucinogenos)\\b"
)
patron_otros_delitos <- paste0(
  "\\b(estafa\\w*|fraude\\w*|secuestr\\w*|trata de personas|polvora|porte ilegal|",
  "armas? de fuego|contrabando|suplant\\w*|ciberdelit\\w*|desaparecid\\w*|abigeato|",
  "pirateria terrestre|amenazas?)\\b"
)
patron_operatividad <- paste0(
  "\\b(captur\\w*|cayo|cayeron|desarticul\\w*|allanamient\\w*|operativ\\w*|",
  "judicializ\\w*|aprehend\\w*|incaut\\w*|megatoma\\w*|bandas?)\\b"
)
patron_politica <- paste0(
  "\\b(frentes? de seguridad|camaras?|pie de fuerza|policias? nuevos|uniformados|",
  "dispositivo de seguridad|patrullaj\\w*|cifras|consejo de seguridad|secretaria de seguridad|",
  "estrategia|percepcion|victimizacion|plan|balance|encuesta|alcalde\\w*|concejo)\\b"
)

## 4.3 Función vectorizada de clasificación ----
# Evalúa en orden de prioridad: delitos contra la vida/integridad (filtrando
# siniestros viales), modalidades específicas de hurto por objeto o contexto,
# hurto sin especificar y finalmente noticias operativas o de política pública.
clasificar_dai_vector <- function(txt) {
  txt <- coalesce(txt, "")
  es_transito <- str_detect(txt, patron_transito)
  case_when(
    str_detect(txt, patron_homicidio) & !(es_transito & !str_detect(txt, "\\b(sicari\\w*|asesin\\w*|homicidio)\\b")) ~ "homicidio",
    str_detect(txt, patron_sexual)                             ~ "delitos_sexuales",
    str_detect(txt, patron_vif)                                ~ "violencia_intrafamiliar",
    str_detect(txt, patron_extorsion)                          ~ "extorsion",
    str_detect(txt, patrones_objeto$hurto_entidades_financieras) ~ "hurto_entidades_financieras",
    str_detect(txt, patrones_directos$hurto_automotores) |
      str_detect(txt, patrones_objeto$hurto_automotores)       ~ "hurto_automotores",
    str_detect(txt, patrones_directos$hurto_motocicletas) |
      str_detect(txt, patrones_objeto$hurto_motocicletas)      ~ "hurto_motocicletas",
    str_detect(txt, patrones_objeto$hurto_bicicletas)          ~ "hurto_bicicletas",
    str_detect(txt, patrones_objeto$hurto_celulares)           ~ "hurto_celulares",
    str_detect(txt, patrones_directos$hurto_residencias) |
      str_detect(txt, patrones_objeto$hurto_residencias)       ~ "hurto_residencias",
    str_detect(txt, patron_hurto) &
      str_detect(txt, patron_otros_hurtos)                     ~ "nodai_otros_hurtos",
    str_detect(txt, patrones_directos$hurto_comercio) |
      str_detect(txt, patrones_objeto$hurto_comercio)          ~ "hurto_comercio",
    str_detect(txt, patrones_directos$hurto_personas) |
      str_detect(txt, patrones_objeto$hurto_personas)          ~ "hurto_personas",
    str_detect(txt, patron_hurto) &
      str_detect(txt, contexto_comercio)                       ~ "hurto_comercio",
    str_detect(txt, patron_hurto) &
      str_detect(txt, contexto_personas)                       ~ "hurto_personas",
    str_detect(txt, patron_lesiones) & !es_transito            ~ "lesiones_personales",
    str_detect(txt, patron_hurto)                              ~ "hurto_no_identificado",
    str_detect(txt, patron_microtrafico)                       ~ "nodai_microtrafico",
    str_detect(txt, patron_otros_delitos)                      ~ "nodai_otros_delitos",
    str_detect(txt, patron_operatividad)                       ~ "nodai_operatividad",
    str_detect(txt, patron_politica)                           ~ "nodai_politica_seguridad",
    TRUE                                                       ~ "nodai_sin_hecho_delictivo"
  )
}

es_dai_especifico <- function(x) !str_starts(x, "nodai_") & x != "hurto_no_identificado"

## 4.4 Asignación jerárquica (Titular -> Resumen -> Cuerpo) ----
# Priorizamos titular, luego resumen y finalmente el cuerpo para evitar que
# menciones secundarias al final de una nota desplacen el hecho principal.
mapa_sdscj <- c(
  homicidio                   = "Homicidio",
  lesiones_personales         = "Lesiones personales",
  hurto_personas              = "Hurto a personas",
  hurto_celulares             = "Hurto a personas",
  hurto_bicicletas            = "Hurto a personas",
  hurto_residencias           = "Hurto a residencias",
  hurto_comercio              = "Hurto a comercio",
  hurto_entidades_financieras = "Hurto a entidades financieras",
  hurto_automotores           = "Hurto de automotores",
  hurto_motocicletas          = "Hurto de motocicletas",
  extorsion                   = "Extorsión",
  delitos_sexuales            = "Delitos sexuales",
  violencia_intrafamiliar     = "Violencia intrafamiliar",
  hurto_no_identificado       = "Hurto (modalidad no identificada)"
)

categorias_dai_estrictas <- setdiff(unname(mapa_sdscj), "Hurto (modalidad no identificada)")

df_clasificado <- df_clasif |>
  mutate(
    clase_titulo  = clasificar_dai_vector(txt_titulo),
    clase_resumen = clasificar_dai_vector(txt_resumen),
    clase_cuerpo  = clasificar_dai_vector(txt_cuerpo),
    modalidad_dai = case_when(
      es_dai_especifico(clase_titulo)             ~ clase_titulo,
      es_dai_especifico(clase_resumen)            ~ clase_resumen,
      es_dai_especifico(clase_cuerpo)             ~ clase_cuerpo,
      clase_titulo  == "hurto_no_identificado"    ~ clase_titulo,
      clase_resumen == "hurto_no_identificado"    ~ clase_resumen,
      clase_cuerpo  == "hurto_no_identificado"    ~ clase_cuerpo,
      clase_titulo  != "nodai_sin_hecho_delictivo" ~ clase_titulo,
      TRUE                                        ~ clase_resumen
    ),
    campo_clasificacion = case_when(
      modalidad_dai == clase_titulo  ~ "titulo",
      modalidad_dai == clase_resumen ~ "resumen",
      TRUE                           ~ "cuerpo"
    ),
    delito_sdscj = coalesce(unname(mapa_sdscj[modalidad_dai]), "No DAI"),
    confianza_dai = case_when(
      delito_sdscj != "No DAI" & campo_clasificacion == "titulo"  ~ "Alta",
      delito_sdscj != "No DAI" & campo_clasificacion == "resumen" ~ "Media",
      delito_sdscj != "No DAI"                                    ~ "Baja",
      TRUE                                                        ~ NA_character_
    ),
    es_dai_estricto  = delito_sdscj %in% categorias_dai_estrictas,
    es_dai_amplio    = es_dai_estricto | delito_sdscj == "Hurto (modalidad no identificada)",
    motivo_exclusion = if_else(es_dai_amplio, NA_character_, str_remove(modalidad_dai, "^nodai_")),
    fecha_imputada   = as.integer(format(fecha, "%d")) == 1L,
    menciona_localidad = str_detect(
      paste(txt_titulo, txt_resumen, txt_cuerpo),
      paste0("\\b", normalizar_texto(localidad), "\\b")
    ),
    texto_corto     = palabras_cuerpo < 30,
    ventana_ene_sep = mes <= 9L
  )

# 5. Almacenamiento en Data Processed ----

columnas_auxiliares <- c(
  "txt_titulo", "txt_resumen", "txt_cuerpo",
  "clase_titulo", "clase_resumen", "clase_cuerpo"
)

## 5.1 Corpus general procesado (insumo para sentometrics y downstream) ----
# Ordenamos por localidad y fecha y asignamos un id único para facilitar la
# trazabilidad entre el parquet procesado y los objetos S3 de sentometrics.
df_procesado_final <- df_clasificado |>
  select(-all_of(columnas_auxiliares)) |>
  arrange(localidad, fecha) |>
  mutate(id = paste0("doc_", row_number()))

archivo_proc_p <- file.path(ruta_salida_proc_dir, "noticias_procesadas.parquet")
write_parquet(df_procesado_final, archivo_proc_p)

## 5.2 Tablas analíticas y de auditoría ----
noticias_dai <- df_procesado_final |> filter(es_dai_amplio)

# Matriz de reclasificación: compara la etiqueta original del scraping frente
# a la categoría SDSCJ asignada para auditar cuántos registros se reasignaron.
tabla_reclasificacion <- df_procesado_final |>
  count(delito_alto_impacto, delito_sdscj, name = "n") |>
  arrange(delito_alto_impacto, desc(n))
write_csv(tabla_reclasificacion, file.path(ruta_salida_tablas, "tabla_reclasificacion_dai.csv"))

# Conteo anual por localidad (2022–2026) desagregado entre DAI amplio, DAI
# estricto y ventana enero–septiembre para verificar cobertura sin vacíos.
tabla_conteo <- noticias_dai |>
  count(localidad, año, name = "noticias_dai") |>
  complete(localidad, año = 2022:2026, fill = list(noticias_dai = 0L)) |>
  left_join(
    noticias_dai |> filter(es_dai_estricto) |> count(localidad, año, name = "noticias_dai_estricto"),
    by = c("localidad", "año")
  ) |>
  left_join(
    noticias_dai |> filter(ventana_ene_sep) |> count(localidad, año, name = "noticias_dai_ene_sep"),
    by = c("localidad", "año")
  ) |>
  mutate(across(starts_with("noticias"), ~ coalesce(.x, 0L)))
write_csv(tabla_conteo, file.path(ruta_salida_tablas, "tabla_conteo_localidad_anio_dai.csv"))

# Muestra aleatoria estratificada de 15 noticias por categoría (mezclada al azar)
# con columnas vacías para revisar manualmente la precisión de las reglas regex.
muestra_validacion <- df_procesado_final |>
  group_by(delito_sdscj) |>
  slice_sample(n = 15) |>
  ungroup() |>
  slice_sample(prop = 1) |>
  transmute(
    localidad, año, titulo, resumen, delito_alto_impacto,
    delito_sdscj, modalidad_dai, campo_clasificacion,
    validacion_correcta = NA_character_, categoria_correcta = NA_character_
  )
write_csv(muestra_validacion, file.path(ruta_salida_tablas, "muestra_validacion_manual_dai.csv"), na = "")

# 6. Resumen Descriptivo y Diagnóstico ----

## 6.1 Estadísticos de volumen léxico ----
metricas_longitud <- data.frame(
  estadistico         = c("minimo", "q1", "mediana", "media", "q3", "maximo"),
  caracteres_original = as.numeric(summary(nchar(cuerpo_original))),
  caracteres_limpio   = as.numeric(summary(nchar(cuerpo_depurado))),
  palabras_limpio     = as.numeric(summary(df_procesado_final$palabras_cuerpo))
)

## 6.2 Comprobación de valores faltantes ----
vars_clave <- c("id", "fecha", "localidad_slug", "titulo", "resumen", "cuerpo", "texto_completo_nlp", "delito_sdscj", "año_mes")
valores_faltantes <- tibble(
  variable = vars_clave,
  nulos    = colSums(is.na(df_procesado_final[vars_clave]))
)

print(metricas_longitud, row.names = FALSE)
print(valores_faltantes, row.names = FALSE)

cat("\n=== Desglose por Categoría DAI (SDSCJ) ===\n")
print(count(df_procesado_final, delito_sdscj, sort = TRUE))
cat("\n=== Desglose por Confianza DAI ===\n")
print(count(noticias_dai, confianza_dai))
