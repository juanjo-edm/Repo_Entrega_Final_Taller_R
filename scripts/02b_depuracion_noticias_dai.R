# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: scripts/02b_depuracion_noticias_dai.R
# ROL: Reclasificación y depuración del corpus de noticias según el catálogo
#      oficial de Delitos de Alto Impacto (DAI) de la SDSCJ.
# AUTOR: Gabriel Arturo Echeverry Castaño (Sub-equipo Datos y Modelado, Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# POR QUÉ EXISTE ESTE SCRIPT:
# La sección 6.3 de scraping_google_news.R clasifica con expresiones regulares
# sin límites de palabra (\\b). Esto produce falsos positivos masivos:
#   - "bar"   coincide con "barrio" y "Barrios Unidos"  -> Hurto a comercio
#   - "local" coincide con "localidad"                  -> Hurto a comercio
#   - "moto"  coincide con "motor"; "rina" con "Marina", etc.
# De 1.034 notas etiquetadas "Hurto a comercio", 793 se activaron solo por
# "bar" o "local". Además, el catálogo original mezcla categorías que no son
# DAI (microtráfico, operativos, política) y omite "hurto a entidades financieras".
#
# CATÁLOGO OFICIAL SDSCJ (11 DAI, boletines 2024-2026):
#   1 Homicidio                 7 Hurto de automotores
#   2 Lesiones personales       8 Hurto de motocicletas
#   3 Hurto a personas*         9 Extorsión
#   4 Hurto a residencias      10 Delitos sexuales
#   5 Hurto a comercio         11 Violencia intrafamiliar
#   6 Hurto a entidades financieras
#   * La SDSCJ reporta además hurto de celulares y de bicicletas como
#     modalidades de hurto a personas; aquí se conservan en `modalidad_dai`.
#
# REGLA DE DECISIÓN:
#   Una nota se conserva si su titular (o, en su defecto, el resumen o el
#   inicio del cuerpo) hace referencia a un hecho de alguno de los 11 DAI,
#   incluso si es una nota de captura u operativo sobre ese delito.
#   Se excluyen: microtráfico, operativos sin delito identificable, política
#   de seguridad, otros delitos (estafa, secuestro, hurto de infraestructura,
#   pólvora...) y notas sin hecho delictivo.
#
# SALIDAS (data/processed/noticias/ y output/tables/):
#   noticias_dai.parquet / .rds                -> base depurada (insumo análisis)
#   noticias_excluidas_no_dai.parquet / .rds   -> trazabilidad de exclusiones
#   tabla_reclasificacion_dai.csv              -> original vs. nueva categoría
#   tabla_conteo_localidad_anio_dai.csv        -> panel de volumen noticioso
#   muestra_validacion_manual_dai.csv          -> 195 notas para validar a mano
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----
library(here)       # Rutas relativas desde la raíz del proyecto
library(conflicted) # Gestión explícita de colisiones de funciones
library(dplyr)      # Manipulación de datos
library(tidyr)      # Remodelado (pivots)
library(stringr)    # Expresiones regulares (motor ICU)
library(stringi)    # Normalización de tildes
library(readr)      # Exportación .csv

## 1.3 Resolución explícita de conflictos ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Rutas relativas ----
ruta_noticias      <- here::here("data", "processed", "noticias")
ruta_salida_tablas <- here::here("output", "tables")
dir.create(ruta_salida_tablas, recursive = TRUE, showWarnings = FALSE)

## 1.5 Lectura/escritura (Parquet con {arrow}; RDS como respaldo) ----
leer_tabla <- function(nombre_base) {
  f_parquet <- file.path(ruta_noticias, paste0(nombre_base, ".parquet"))
  f_rds     <- file.path(ruta_noticias, paste0(nombre_base, ".rds"))
  hay_arrow <- requireNamespace("arrow", quietly = TRUE)

  if (file.exists(f_parquet) && hay_arrow) return(arrow::read_parquet(f_parquet))
  if (file.exists(f_rds))                  return(readRDS(f_rds))

  stop(
    "No se pudo leer '", nombre_base, "'.\n",
    "  .parquet existe: ", file.exists(f_parquet), " | arrow instalado: ", hay_arrow, "\n",
    "  .rds existe:     ", file.exists(f_rds), "\n",
    "  Carpeta revisada: ", ruta_noticias, "\n",
    "  Archivos en la carpeta: ", paste(list.files(ruta_noticias), collapse = ", "),
    call. = FALSE
  )
}

escribir_tabla <- function(df, nombre_base) {
  saveRDS(df, file.path(ruta_noticias, paste0(nombre_base, ".rds")))
  if (requireNamespace("arrow", quietly = TRUE)) {
    arrow::write_parquet(df, file.path(ruta_noticias, paste0(nombre_base, ".parquet")))
  }
}

# 2. Carga del Corpus ----
noticias <- leer_tabla("noticias_con_sentimiento") |>
  mutate(
    fecha = as.Date(fecha),
    año   = as.integer(año),
    mes   = as.integer(mes)
  )

message(">>> Corpus cargado: ", nrow(noticias), " noticias.")

# 3. Normalización de Texto ----
# Minúsculas, sin tildes ni signos; el cuerpo se recorta para evitar que las
# "noticias relacionadas" al pie de página contaminen la clasificación.
normalizar <- function(x) {
  x |>
    stri_trans_general("Latin-ASCII") |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9 ]", " ") |>
    str_squish()
}

noticias <- noticias |>
  mutate(
    txt_titulo  = normalizar(titulo),
    txt_resumen = normalizar(resumen),
    txt_cuerpo  = normalizar(str_sub(cuerpo, 1, 1500))
  )

# 4. Diccionarios DAI con Límites de Palabra ----

## 4.1 Señal genérica de hurto ----
verbo_hurto <- paste0(
  "(hurt\\w*|rob(?!(ust|ot|ert|led|ins|le\\b|les\\b))\\w*|atraco|atracos|atraca|atracan|atracaron|",
  "atracado|atracada|atracador\\w*|asalto|asaltos|asaltan|asaltaron|asaltado\\w*|",
  "asaltante\\w*|saque\\w*|desvalij\\w*|escopolamin\\w*|rompevidrios|raponaz\\w*|raponer\\w*|cosquille\\w*|fleteo\\w*|fletero\\w*|",
  "ladron|ladrones|ladrona\\w*|apartamenter\\w*|robacarros|robamotos|halado\\w*)"
)
patron_hurto <- paste0("\\b", verbo_hurto, "\\b")

## 4.2 Objetos de hurto por modalidad ----
# Se exige que verbo y objeto aparezcan a máximo 4 palabras de distancia
# (en cualquier orden) para no confundir "ladrones en moto" con hurto de moto.
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

# Orden verbo -> objeto ("robaron el celular"), o bien objeto -> participio
# ("celular robado"). No se usa objeto -> verbo conjugado para no confundir
# el medio con el botín ("ladrones en moto robaron a una mujer").
participio_hurto <- "(robad[oa]s?|hurtad[oa]s?|saquead[oa]s?|desvalijad[oa]s?)"
construir_patron_objeto <- function(objeto) {
  paste0(
    "\\b", verbo_hurto, "\\b(\\s+\\w+){0,4}\\s+\\b", objeto, "\\b|",
    "\\b", objeto, "\\b(\\s+\\w+){0,3}\\s+\\b", participio_hurto, "\\b"
  )
}
patrones_objeto <- lapply(objetos_hurto, construir_patron_objeto)

# Expresiones inequívocas que no requieren verbo cercano
patrones_directos <- list(
  hurto_personas    = "\\b(hurto a personas|robo a personas|atracos?|escopolamin\\w*|raponaz\\w*|cosquille\\w*|fleteo\\w*|fleteros?|paseo millonario|escopolamina|burundanga)\\b",
  hurto_residencias = "\\b(hurto a residencias|robo a residencias|apartamenteros?|hurto a viviendas?)\\b",
  hurto_comercio    = "\\b(hurto a comercio|robo a comercio|hurto a establecimientos?)\\b",
  hurto_automotores = "\\b(hurto de (automotores|vehiculos|carros)|rompevidrios|robacarros|halado de vehiculos?|desguazadero\\w*|deshuesadero\\w*|recuper\\w*( \\w+){0,3} (vehiculos?|carros?|camion(es)?|camionetas?|automotor(es)?|automoviles?))\\b",
  hurto_motocicletas = "\\b(hurto de motocicletas|robamotos|halado de motos?|(desguazadero|deshuesadero)s? de motos|recuper\\w*( \\w+){0,3} (motos?|motocicletas?))\\b"
)

## 4.2b Respaldo por coocurrencia (hurto + contexto en el mismo campo) ----
# Se aplica solo cuando ninguna regla de proximidad identificó la modalidad.
contexto_comercio <- paste0("\\b", objetos_hurto$hurto_comercio, "\\b")
contexto_personas <- paste0(
  "\\b(pasajeros?|transmilenio|sitp|paraderos?|transeuntes?|peatones?|via publica|",
  "en (plena )?(via|calle)|relojes?|reloj|cadenas?|joyas?|billeteras?|bolsos?|morral(es)?|mochilas?)\\b"
)

## 4.3 Delitos contra la vida, integridad y libertad ----
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
patron_transito <- "\\b(accidente\\w*|choque\\w*|siniestro vial|atropell\\w*|volcamiento|colision)\\b"

## 4.4 Motivos de exclusión (no DAI) ----
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

# 5. Clasificación por Campo de Texto ----

## 5.1 Función que asigna la modalidad DAI a un vector de texto ----
# Orden de prioridad: delitos contra la vida y la libertad primero; luego
# hurtos de objeto específico; lesiones; y por último hurto genérico.
clasificar_dai <- function(txt) {
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

## 5.2 Cascada titular -> resumen -> cuerpo ----
# Se usa el primer campo que identifica una modalidad DAI específica; si
# ninguno lo hace, se acepta un hurto genérico; si tampoco, el motivo de
# exclusión que arroje el titular (o el resumen si el titular no dice nada).
es_dai_especifico <- function(x) !str_starts(x, "nodai_") & x != "hurto_no_identificado"

noticias <- noticias |>
  mutate(
    clase_titulo  = clasificar_dai(txt_titulo),
    clase_resumen = clasificar_dai(txt_resumen),
    clase_cuerpo  = clasificar_dai(txt_cuerpo),
    modalidad_dai = case_when(
      es_dai_especifico(clase_titulo)          ~ clase_titulo,
      es_dai_especifico(clase_resumen)         ~ clase_resumen,
      es_dai_especifico(clase_cuerpo)          ~ clase_cuerpo,
      clase_titulo  == "hurto_no_identificado" ~ clase_titulo,
      clase_resumen == "hurto_no_identificado" ~ clase_resumen,
      clase_cuerpo  == "hurto_no_identificado" ~ clase_cuerpo,
      clase_titulo != "nodai_sin_hecho_delictivo" ~ clase_titulo,
      TRUE                                      ~ clase_resumen
    ),
    campo_clasificacion = case_when(
      modalidad_dai == clase_titulo  ~ "titulo",
      modalidad_dai == clase_resumen ~ "resumen",
      TRUE                           ~ "cuerpo"
    )
  )

## 5.3 Agregación al catálogo oficial de 11 DAI ----
noticias <- noticias |>
  mutate(
    delito_sdscj = case_when(
      modalidad_dai == "homicidio"                   ~ "Homicidio",
      modalidad_dai == "lesiones_personales"         ~ "Lesiones personales",
      modalidad_dai %in% c("hurto_personas", "hurto_celulares", "hurto_bicicletas") ~ "Hurto a personas",
      modalidad_dai == "hurto_residencias"           ~ "Hurto a residencias",
      modalidad_dai == "hurto_comercio"              ~ "Hurto a comercio",
      modalidad_dai == "hurto_entidades_financieras" ~ "Hurto a entidades financieras",
      modalidad_dai == "hurto_automotores"           ~ "Hurto de automotores",
      modalidad_dai == "hurto_motocicletas"          ~ "Hurto de motocicletas",
      modalidad_dai == "extorsion"                   ~ "Extorsión",
      modalidad_dai == "delitos_sexuales"            ~ "Delitos sexuales",
      modalidad_dai == "violencia_intrafamiliar"     ~ "Violencia intrafamiliar",
      modalidad_dai == "hurto_no_identificado"       ~ "Hurto (modalidad no identificada)",
      TRUE                                           ~ "No DAI"
    ),
    # Confianza: alta si lo identifica el titular, media el resumen, baja el cuerpo
    confianza_dai = case_when(
      !(delito_sdscj %in% c("No DAI")) & campo_clasificacion == "titulo"  ~ "Alta",
      !(delito_sdscj %in% c("No DAI")) & campo_clasificacion == "resumen" ~ "Media",
      !(delito_sdscj %in% c("No DAI"))                                    ~ "Baja",
      TRUE                                                                ~ NA_character_
    ),
    # Base estricta: solo las 11 categorías oficiales identificadas
    es_dai_estricto = delito_sdscj %in% c(
      "Homicidio", "Lesiones personales", "Hurto a personas", "Hurto a residencias",
      "Hurto a comercio", "Hurto a entidades financieras", "Hurto de automotores",
      "Hurto de motocicletas", "Extorsión", "Delitos sexuales", "Violencia intrafamiliar"
    ),
    # Base amplia: añade notas de hurto cuya modalidad el texto no permite precisar
    es_dai_amplio = es_dai_estricto | delito_sdscj == "Hurto (modalidad no identificada)",
    motivo_exclusion = if_else(es_dai_amplio, NA_character_, str_remove(modalidad_dai, "^nodai_"))
  )

# 6. Banderas de Calidad (no filtran; documentan) ----
noticias <- noticias |>
  mutate(
    # Fecha imputada: el scraper asignó el primer día del bloque mensual
    fecha_imputada  = as.integer(format(fecha, "%d")) == 1L,
    # La nota nombra explícitamente la localidad asignada
    menciona_localidad = str_detect(
      paste(txt_titulo, txt_resumen, txt_cuerpo),
      paste0("\\b", normalizar(localidad), "\\b")
    ),
    # Texto corto: el cuerpo es solo el snippet del RSS (< 30 palabras)
    texto_corto     = palabras_cuerpo < 30,
    # Ventana homologable con 2026 (enero-septiembre)
    ventana_ene_sep = mes <= 9L
  )

# 7. Partición y Exportación ----

## 7.1 Bases depuradas ----
columnas_aux <- c("txt_titulo", "txt_resumen", "txt_cuerpo",
                  "clase_titulo", "clase_resumen", "clase_cuerpo")

noticias_dai <- noticias |>
  filter(es_dai_amplio) |>
  select(-all_of(columnas_aux)) |>
  arrange(localidad, fecha)

noticias_excluidas <- noticias |>
  filter(!es_dai_amplio) |>
  select(-all_of(columnas_aux)) |>
  arrange(motivo_exclusion, localidad, fecha)

escribir_tabla(noticias_dai,       "noticias_dai")
escribir_tabla(noticias_excluidas, "noticias_excluidas_no_dai")

## 7.2 Tabla de reclasificación (original vs. SDSCJ) ----
tabla_reclasificacion <- noticias |>
  count(delito_alto_impacto, delito_sdscj, name = "n") |>
  arrange(delito_alto_impacto, desc(n))
write_csv(tabla_reclasificacion, file.path(ruta_salida_tablas, "tabla_reclasificacion_dai.csv"))

## 7.3 Panel de volumen noticioso localidad x año ----
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

## 7.4 Muestra estratificada para validación manual ----
# 15 notas por categoría (13 categorías = 195 notas) para medir la precisión
# del clasificador. Las columnas de validación quedan vacías para llenarlas a
# mano: `validacion_correcta` (SI/NO) y `categoria_correcta` (solo si es NO).
muestra_validacion <- noticias |>
  group_by(delito_sdscj) |>
  slice_sample(n = 15) |>
  ungroup() |>
  slice_sample(prop = 1) |>
  transmute(id, localidad, año, titulo, resumen, delito_alto_impacto,
            delito_sdscj, modalidad_dai, campo_clasificacion,
            validacion_correcta = NA_character_, categoria_correcta = NA_character_)
write_csv(muestra_validacion, file.path(ruta_salida_tablas, "muestra_validacion_manual_dai.csv"), na = "")

# 8. Diagnóstico en Consola ----
message("\n=== Resultado de la depuración DAI ===")
message("Corpus original:            ", nrow(noticias))
message("Base DAI amplia (conserva): ", nrow(noticias_dai))
message("  de ellas DAI estricto:    ", sum(noticias_dai$es_dai_estricto))
message("Excluidas (no DAI):         ", nrow(noticias_excluidas))
print(count(noticias_dai, confianza_dai))
print(count(noticias, delito_sdscj, sort = TRUE))
print(count(noticias_excluidas, motivo_exclusion, sort = TRUE))
print(count(noticias_dai, año))
