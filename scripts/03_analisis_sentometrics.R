# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/03_analisis_sentometrics.R
# ROL: Pipeline Integral de Sentometrics (3 Modalidades Objetivo, 36 Series)
# AUTORES: Juan José Echeverry, Sergio López, Olga Lucía Ramírez (Grupo 3)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE:
#   - data/processed/sentometrics_pipeline.rds (único artefacto S3 intermedio)
#   - data/processed/panel_consolidado_localidad_anual.parquet
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías y resolución de conflictos ----
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(stringi)
library(data.table)
library(syuzhet)
library(sentometrics)
library(glmnet)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("first",  "dplyr", quiet = TRUE)

## 1.3 Rutas relativas ----
ruta_proc          <- here::here("data", "processed")
archivo_noticias   <- file.path(ruta_proc, "03_noticias", "noticias_procesadas.parquet")
archivo_delitos    <- file.path(ruta_proc, "02_poblacion", "panel_delitos_poblacion_mensual.parquet")
archivo_clusters   <- file.path(ruta_proc, "clusters_localidades_kmeans.parquet")

stopifnot(file.exists(archivo_noticias))
stopifnot(file.exists(archivo_delitos))

# 2. Fase 1: Corpus y Construcción de Features (T-05, T-06, T-07) ----

## 2.1 Carga de noticias depuradas, panel mensual SIEDCO y clústeres K-Means ----
df_noticias <- arrow::read_parquet(archivo_noticias)
panel_delitos_mensual <- arrow::read_parquet(archivo_delitos)

panel_delitos <- panel_delitos_mensual |>
  group_by(codigo_localidad, localidad, año) |>
  summarise(
    hurto_personas         = sum(hurto_personas, na.rm = TRUE),
    hurto_residencias      = sum(hurto_residencias, na.rm = TRUE),
    hurto_motos            = sum(hurto_motos, na.rm = TRUE),
    poblacion              = first(poblacion),
    tasa_hurto_personas    = round((hurto_personas / poblacion) * 100000, 2),
    tasa_hurto_residencias = round((hurto_residencias / poblacion) * 100000, 2),
    tasa_hurto_motos       = round((hurto_motos / poblacion) * 100000, 2),
    tasa_hurto_total       = round(((hurto_personas + hurto_residencias + hurto_motos) / poblacion) * 100000, 2),
    .groups                = "drop"
  )

# Filtrar estrictamente el corpus comparable de las 3 modalidades objetivo SIEDCO
modalidades_objetivo_noticias <- c(
  "Hurto a personas",
  "Hurto a residencias",
  "Hurto de motocicletas"
)
df_noticias_modelo <- df_noticias |>
  filter(delito_sdscj %in% modalidades_objetivo_noticias)

stopifnot(
  nrow(df_noticias_modelo) > 0,
  length(unique(df_noticias_modelo$localidad)) == 19L,
  all(df_noticias_modelo$delito_sdscj %in% modalidades_objetivo_noticias)
)

if (!file.exists(archivo_clusters)) {
  source(here::here("scripts", "04_clustering_kmeans.R"), local = new.env())
}
df_clusters <- arrow::read_parquet(archivo_clusters)

## 2.2 Construcción de textos y 6 indicadores binarios [0, 1] (Clústeres y Modalidades) ----
df_base_corpus <- df_noticias_modelo |>
  select(-any_of(c("cluster_id", "cluster_nombre", "perfil_seguridad"))) |>
  left_join(
    df_clusters |> select(localidad, cluster_id, cluster_nombre),
    by = "localidad"
  ) |>
  mutate(
    id    = paste0("doc_", row_number()),
    date  = as.Date(fecha),
    texts = str_squish(paste(
      coalesce(titulo, ""),
      coalesce(resumen, ""),
      str_sub(coalesce(cuerpo, ""), 1, 800),
      sep = ". "
    )),
    # 3 features de clústeres K-Means (partición exhaustiva y excluyente)
    c_centro      = as.numeric(cluster_nombre == "Céntrico e Institucional"),
    c_comercial   = as.numeric(cluster_nombre == "Comercial y Automotor"),
    c_residencial = as.numeric(cluster_nombre == "Residencial y Periférico"),
    # 3 features temáticas exclusivas de las modalidades de hurto analizadas
    tema_hurto_personas    = as.numeric(delito_sdscj == "Hurto a personas"),
    tema_hurto_residencias = as.numeric(delito_sdscj == "Hurto a residencias"),
    tema_hurto_motos       = as.numeric(delito_sdscj == "Hurto de motocicletas")
  )

cols_features <- c(
  "c_centro", "c_comercial", "c_residencial",
  "tema_hurto_personas", "tema_hurto_residencias", "tema_hurto_motos"
)

# Auditoría estricta de contrato T-01 / T-07: cero guiones '-', cero NAs y partición exacta
stopifnot(!any(str_detect(cols_features, "-")))
stopifnot(all(!is.na(df_base_corpus$date)))
stopifnot(all(!is.na(df_base_corpus$texts)))
stopifnot(all(rowSums(df_base_corpus[, c("c_centro", "c_comercial", "c_residencial")]) == 1))
stopifnot(all(rowSums(df_base_corpus[, c("tema_hurto_personas", "tema_hurto_residencias", "tema_hurto_motos")]) == 1))

## 2.3 Creación del objeto S3 sento_corpus (T-07) ----
df_sento_input <- df_base_corpus |>
  select(id, date, texts, all_of(cols_features)) |>
  as.data.frame()

corpus_sento <- sentometrics::sento_corpus(
  corpusdf = df_sento_input,
  do.clean = FALSE
)

message("✔ [T-07] Objeto sento_corpus creado con ", nrow(df_sento_input), " noticias objetivo y ", length(cols_features), " features.")

# 3. Fase 2: Léxicos, Modificadores de Valencia y Sentimiento (T-09, T-10, T-11) ----

## 3.1 Construcción de diccionarios de polaridad en español (nrc_es y crimen_es) ----
nrc_es_crudo <- syuzhet::get_sentiment_dictionary("nrc", language = "spanish")
lex_nrc_es <- nrc_es_crudo |>
  filter(sentiment %in% c("positive", "negative")) |>
  mutate(
    x = str_to_lower(str_trim(word)),
    y = ifelse(sentiment == "positive", 1.0, -1.0)
  ) |>
  filter(!str_detect(x, "\\s+"), nchar(x) > 1) |>
  group_by(x) |>
  summarise(y = round(mean(y), 4), .groups = "drop") |>
  filter(y != 0) |>
  as.data.frame()

# Léxico especializado en seguridad ciudadana y criminalidad urbana de Bogotá
lex_crimen_bogota <- tribble(
  ~x,                ~y,
  # Términos de alta negatividad (delitos y violencia)
  "homicidio",      -1.0,  "homicidios",     -1.0,  "asesinato",      -1.0,
  "asesinado",      -1.0,  "asesinada",      -1.0,  "sicariato",      -1.0,
  "sicario",        -1.0,  "sicarios",       -1.0,  "feminicidio",    -1.0,
  "masacre",        -1.0,  "cadáver",        -0.9,  "cadáveres",      -0.9,
  "embolsado",      -1.0,  "embolsados",     -1.0,  "balacera",       -0.9,
  "tiroteo",        -0.9,  "baleado",        -0.9,  "apuñalado",      -0.9,
  "puñalada",       -0.8,  "extorsión",      -0.9,  "extorsiones",    -0.9,
  "secuestro",      -1.0,  "violación",      -1.0,  "abuso",          -0.8,
  "atraco",         -0.9,  "atracos",        -0.9,  "atracador",      -0.9,
  "atracadores",    -0.9,  "robo",           -0.8,  "robos",          -0.8,
  "robaron",        -0.8,  "hurtaron",       -0.8,  "hurto",          -0.7,
  "hurtos",         -0.7,  "asalto",         -0.8,  "asaltantes",     -0.8,
  "fleteo",         -0.9,  "fleteros",       -0.9,  "escopolamina",   -0.9,
  "burundanga",     -0.9,  "cosquilleo",     -0.7,  "raponazo",       -0.7,
  "rompevidrios",   -0.7,  "apartamenteros", -0.8,  "halado",         -0.7,
  "desguazadero",   -0.8,  "microtráfico",   -0.8,  "narcomenudeo",   -0.8,
  "delincuencia",   -0.8,  "delincuentes",   -0.8,  "criminales",     -0.8,
  "banda",          -0.6,  "bandas",         -0.6,  "inseguridad",    -0.8,
  "miedo",          -0.7,  "temor",          -0.7,  "pánico",         -0.8,
  "zozobra",        -0.8,  "impunidad",      -0.8,  "víctima",        -0.6,
  "víctimas",       -0.6,  "herido",         -0.7,  "heridos",        -0.7,
  "lesionado",      -0.6,  "peligro",        -0.7,  "amenaza",        -0.7,
  "amenazas",       -0.7,  "denuncia",       -0.4,  "denuncias",      -0.4,
  # Términos positivos de respuesta institucional, judicialización y prevención
  "captura",         0.7,  "capturas",        0.7,  "capturado",       0.7,
  "capturados",      0.7,  "desarticulación", 0.9,  "desarticulada",   0.9,
  "desarticulan",    0.9,  "recuperación",    0.8,  "recuperado",      0.8,
  "recuperados",     0.8,  "incautación",     0.7,  "incautaron",      0.7,
  "rescate",         0.8,  "rescatado",       0.8,  "judicialización", 0.8,
  "judicializados",  0.8,  "condena",         0.6,  "condenado",       0.6,
  "esclarecimiento", 0.8,  "reducción",       0.8,  "disminución",     0.8,
  "disminuyó",       0.8,  "bajó",            0.4,  "prevención",      0.7,
  "protección",      0.7,  "seguridad",       0.5,  "seguro",          0.7,
  "segura",          0.7,  "patrullaje",      0.6,  "operativo",       0.5,
  "operativos",      0.5,  "megatoma",        0.6,  "convivencia",     0.8,
  "tranquilidad",    0.8,  "justicia",        0.7,  "apoyo",           0.5
) |>
  group_by(x) |>
  summarise(y = mean(y), .groups = "drop") |>
  as.data.frame()

## 3.2 Tabla de modificadores de valencia en español (valenceIn: x, y, t) ----
# Convención sentometrics (list_valence_shifters):
# t = 1 (negadores, y = -1.0), t = 2 (amplificadores, y = 1.8),
# t = 3 (atenuadores, y = 0.2), t = 4 (adversativos, y = -1.0)
tabla_valence_es <- tribble(
  ~x,               ~y,   ~t,
  # Negadores (t = 1)
  "no",            -1.0,  1L,
  "nunca",         -1.0,  1L,
  "jamás",         -1.0,  1L,
  "sin",           -1.0,  1L,
  "ni",            -1.0,  1L,
  "tampoco",       -1.0,  1L,
  "ningún",        -1.0,  1L,
  "ninguna",       -1.0,  1L,
  # Amplificadores (t = 2)
  "muy",            1.8,  2L,
  "altamente",      1.8,  2L,
  "sumamente",      1.8,  2L,
  "extremadamente", 1.8,  2L,
  "demasiado",      1.8,  2L,
  "gravemente",     1.8,  2L,
  "brutalmente",    1.8,  2L,
  "masivamente",    1.8,  2L,
  "totalmente",     1.8,  2L,
  "completamente",  1.8,  2L,
  "bastante",       1.5,  2L,
  "fuerte",         1.5,  2L,
  # Atenuadores / Deamplificadores (t = 3)
  "poco",           0.2,  3L,
  "apenas",         0.2,  3L,
  "levemente",      0.2,  3L,
  "ligeramente",    0.2,  3L,
  "parcialmente",   0.2,  3L,
  "casi",           0.4,  3L,
  # Adversativos (t = 4)
  "pero",          -1.0,  4L,
  "aunque",        -1.0,  4L,
  "obstante",      -1.0,  4L,
  "embargo",       -1.0,  4L
) |>
  as.data.frame()

lexicons_es <- sentometrics::sento_lexicons(
  lexiconsIn = list(
    nrc_es    = lex_nrc_es,
    crimen_es = lex_crimen_bogota
  ),
  valenceIn = tabla_valence_es
)
attr(lexicons_es, "valence_table_full") <- tabla_valence_es

message("✔ [T-09] Diccionarios construidos en memoria (nrc_es + crimen_es + valenceIn).")

## 3.3 Cómputo de sentimiento a nivel documento: proportionalPol vs TFIDF (T-10) ----
sentiment_scores <- sentometrics::compute_sentiment(
  x           = corpus_sento,
  lexicons    = lexicons_es,
  how         = "proportionalPol",
  do.sentence = FALSE
)

sentiment_tfidf <- sentometrics::compute_sentiment(
  x           = corpus_sento,
  lexicons    = lexicons_es,
  how         = "TFIDF",
  do.sentence = FALSE
)

# Cálculo exacto del puntaje documental por léxico (los 3 clústeres son exhaustivos y excluyentes)
df_sent_doc <- as_tibble(sentiment_scores) |>
  transmute(
    id = id,
    word_count = word_count,
    score_nrc_es = round(
      `nrc_es--c_centro` + `nrc_es--c_comercial` + `nrc_es--c_residencial`,
      4
    ),
    score_crimen_es = round(
      `crimen_es--c_centro` + `crimen_es--c_comercial` + `crimen_es--c_residencial`,
      4
    ),
    sentimiento_score = round(0.5 * score_nrc_es + 0.5 * score_crimen_es, 4)
  ) |>
  left_join(
    as_tibble(sentiment_tfidf) |>
      transmute(
        id = id,
        score_tfidf_compuesto = round(
          0.5 * (`nrc_es--c_centro` + `nrc_es--c_comercial` + `nrc_es--c_residencial`) +
            0.5 * (`crimen_es--c_centro` + `crimen_es--c_comercial` + `crimen_es--c_residencial`),
          4
        )
      ),
    by = "id"
  )

attr(sentiment_scores, "comparacion_metodologica") <- list(
  correlacion_propPol_tfidf = cor(
    df_sent_doc$sentimiento_score,
    df_sent_doc$score_tfidf_compuesto,
    use = "complete.obs"
  ),
  media_nrc_es      = mean(df_sent_doc$score_nrc_es, na.rm = TRUE),
  media_crimen_es   = mean(df_sent_doc$score_crimen_es, na.rm = TRUE),
  media_combinada   = mean(df_sent_doc$sentimiento_score, na.rm = TRUE)
)

message("✔ [T-10] Puntajes de sentimiento calculados en memoria (how = 'proportionalPol').")

## 3.4 Enriquecimiento del dataset objetivo (993 docs) y actualización de noticias_procesadas.parquet ----
df_noticias_enriquecida <- df_noticias_modelo |>
  select(-any_of(c(
    "id", "word_count", "score_nrc_es", "score_crimen_es",
    "score_tfidf_compuesto", "sentimiento_score", "sentimiento_categoria",
    "cluster_id", "cluster_nombre", "perfil_seguridad"
  ))) |>
  mutate(id = paste0("doc_", row_number())) |>
  left_join(df_sent_doc, by = "id") |>
  left_join(
    df_clusters |> select(localidad, cluster_id, cluster_nombre, perfil_seguridad),
    by = "localidad"
  ) |>
  mutate(
    sentimiento_categoria = case_when(
      sentimiento_score < -0.02 ~ "Negativo",
      sentimiento_score >  0.02 ~ "Positivo",
      TRUE                      ~ "Neutro"
    )
  )

# Enriquecimiento auxiliar sobre las 3.916 noticias en disco (sin alterar corpus_sento)
# para preservar la referencia de recolección y la comparación espacial en Cuaderno 02.
df_corpus_aux_3916 <- df_noticias |>
  mutate(
    id    = paste0("ref_", row_number()),
    date  = as.Date(fecha),
    texts = str_squish(paste(
      coalesce(titulo, ""),
      coalesce(resumen, ""),
      str_sub(coalesce(cuerpo, ""), 1, 800),
      sep = ". "
    )),
    todas = 1.0
  )
corpus_aux_3916 <- sentometrics::sento_corpus(
  corpusdf = as.data.frame(df_corpus_aux_3916 |> select(id, date, texts, todas)),
  do.clean = FALSE
)
sent_aux_3916 <- sentometrics::compute_sentiment(
  x           = corpus_aux_3916,
  lexicons    = lexicons_es,
  how         = "proportionalPol",
  do.sentence = FALSE
)
df_sent_aux <- as_tibble(sent_aux_3916) |>
  transmute(
    id                = id,
    word_count        = word_count,
    score_nrc_es      = round(`nrc_es--todas`, 4),
    score_crimen_es   = round(`crimen_es--todas`, 4),
    sentimiento_score = round(0.5 * score_nrc_es + 0.5 * score_crimen_es, 4)
  )
df_noticias_completo <- df_noticias |>
  select(-any_of(c(
    "id", "word_count", "score_nrc_es", "score_crimen_es",
    "score_tfidf_compuesto", "sentimiento_score", "sentimiento_categoria",
    "cluster_id", "cluster_nombre", "perfil_seguridad", "es_objetivo_3mod"
  ))) |>
  mutate(
    id               = paste0("ref_", row_number()),
    es_objetivo_3mod = delito_sdscj %in% modalidades_objetivo_noticias
  ) |>
  left_join(df_sent_aux, by = "id") |>
  left_join(
    df_clusters |> select(localidad, cluster_id, cluster_nombre, perfil_seguridad),
    by = "localidad"
  ) |>
  mutate(
    sentimiento_categoria = case_when(
      sentimiento_score < -0.02 ~ "Negativo",
      sentimiento_score >  0.02 ~ "Positivo",
      TRUE                      ~ "Neutro"
    )
  )

arrow::write_parquet(df_noticias_completo, archivo_noticias)
message("✔ noticias_procesadas.parquet actualizado en disco (", nrow(df_noticias_completo), " recopiladas; ", sum(df_noticias_completo$es_objetivo_3mod), " de las 3 modalidades objetivo).")

# Extracción oficial con peakdocs() sobre las 993 noticias objetivo (T-11)
ids_peak_both <- sentometrics::peakdocs(sentiment_scores, n = 25, type = "both")
ids_peak_neg  <- sentometrics::peakdocs(sentiment_scores, n = 25, type = "neg")
ids_peak_pos  <- sentometrics::peakdocs(sentiment_scores, n = 25, type = "pos")

# Tabla de consulta de documentos pico globales y por localidad
peak_por_localidad <- df_noticias_enriquecida |>
  group_by(localidad) |>
  arrange(sentimiento_score) |>
  slice(unique(c(1:5, (n() - 4):n()))) |>
  ungroup()

tabla_peak_docs <- df_noticias_enriquecida |>
  mutate(
    es_pico_global = id %in% unique(c(ids_peak_both, ids_peak_neg, ids_peak_pos)),
    tipo_pico = case_when(
      id %in% ids_peak_neg ~ "Pico Negativo Global",
      id %in% ids_peak_pos ~ "Pico Positivo Global",
      id %in% peak_por_localidad$id & sentimiento_score < 0 ~ "Extremo Negativo Local",
      id %in% peak_por_localidad$id & sentimiento_score > 0 ~ "Extremo Positivo Local",
      TRUE ~ "Regular"
    )
  ) |>
  select(
    id, fecha, año, mes, localidad, cluster_nombre, fuente,
    delito_sdscj, modalidad_dai, es_dai_estricto, confianza_dai,
    titulo, resumen, enlace, word_count,
    score_nrc_es, score_crimen_es, sentimiento_score,
    sentimiento_categoria, es_pico_global, tipo_pico
  ) |>
  arrange(sentimiento_score)

objeto_04_peak_docs <- list(
  peak_ids_both   = ids_peak_both,
  peak_ids_neg    = ids_peak_neg,
  peak_ids_pos    = ids_peak_pos,
  tabla_completa  = as.data.table(tabla_peak_docs),
  top_criticas    = as.data.table(tabla_peak_docs |> filter(tipo_pico != "Regular"))
)

message("✔ [T-11] Catálogo peakdocs() armado en memoria (", nrow(tabla_peak_docs), " noticias objetivo).")

# 4. Fase 3: Series de Tiempo Multidimensionales (T-13, T-14, T-15) ----

## 4.1 Configuración parsimoniosa de ctr_agg y cálculo de sento_measures (36 series) ----
control_agg <- sentometrics::ctr_agg(
  howWithin      = "proportionalPol",
  howDocs        = "proportional",
  howTime        = c("linear", "exponential", "beta"),
  by             = "month",
  lag            = 6,
  alphasExp      = 0.5,
  aBeta          = 2,
  bBeta          = 2,
  do.ignoreZeros = TRUE,
  fill           = "zero"
)

medidas_sento <- sentometrics::sento_measures(
  sento_corpus = corpus_sento,
  lexicons     = lexicons_es,
  ctr          = control_agg
)

medidas_sento <- sentometrics::measures_fill(medidas_sento, fill = "zero")
stopifnot(ncol(medidas_sento$measures) - 1L == 36L)
message("✔ [T-13] Medidas calculadas: ", ncol(medidas_sento$measures) - 1L, " series mensuales (2 léxicos × 6 features × 3 curvas).")

## 4.2 Remodelado en formato Long y Wide para Shiny (T-14) ----
dt_measures_wide <- data.table::as.data.table(medidas_sento)

# Diccionario de etiquetas legibles para features (3 clústeres + 3 modalidades)
mapa_etiquetas_features <- c(
  c_centro               = "Clúster: Céntrico e Institucional",
  c_comercial            = "Clúster: Comercial y Automotor",
  c_residencial          = "Clúster: Residencial y Periférico",
  tema_hurto_personas    = "Modalidad: Hurto a Personas",
  tema_hurto_residencias = "Modalidad: Hurto a Residencias",
  tema_hurto_motos       = "Modalidad: Hurto de Motocicletas"
)

df_measures_long <- as_tibble(dt_measures_wide) |>
  pivot_longer(
    cols      = -date,
    names_to  = "serie_id",
    values_to = "valor"
  ) |>
  separate(
    col    = serie_id,
    into   = c("lexicon", "feature", "time"),
    sep    = "--",
    remove = FALSE
  ) |>
  mutate(
    grupo_feature = case_when(
      str_starts(feature, "c_")    ~ "Clúster Territorial",
      str_starts(feature, "tema_") ~ "Modalidad de Hurto",
      TRUE                         ~ "Otro"
    ),
    feature_label = coalesce(unname(mapa_etiquetas_features[feature]), feature),
    lexicon_label = case_when(
      lexicon == "nrc_es"    ~ "Léxico General (NRC Español)",
      lexicon == "crimen_es" ~ "Léxico Seguridad y Crimen Bogotá",
      TRUE                   ~ lexicon
    )
  )

# Control de auditoría: verificar que todas las series tengan grupo_feature válido
stopifnot(all(df_measures_long$grupo_feature != "Otro"))

objeto_06_measures_long <- list(
  long = as.data.table(df_measures_long),
  wide = dt_measures_wide
)
message("✔ [T-14] Series reestructuradas en memoria (", nrow(df_measures_long), " filas en formato long).")

## 4.3 Índice global ponderado y fechas pico con peakdates() (T-15) ----
medidas_global_dt <- stats::aggregate(medidas_sento, do.global = TRUE)
fechas_pico_ambas <- sentometrics::peakdates(medidas_sento, n = 8, type = "both")
fechas_pico_neg   <- sentometrics::peakdates(medidas_sento, n = 8, type = "neg")
fechas_pico_pos   <- sentometrics::peakdates(medidas_sento, n = 8, type = "pos")

df_global_index <- as_tibble(medidas_global_dt) |>
  mutate(
    date      = as.Date(date),
    es_pico   = date %in% as.Date(c(fechas_pico_ambas, fechas_pico_neg)),
    tipo_pico = case_when(
      date %in% as.Date(fechas_pico_neg) ~ "Pico de Alarma / Negatividad",
      date %in% as.Date(fechas_pico_pos) ~ "Pico Positivo / Operatividad",
      TRUE                               ~ "Normal"
    )
  )

objeto_07_global_index <- list(
  serie_global      = as.data.table(df_global_index),
  peakdates_both    = as.Date(fechas_pico_ambas),
  peakdates_neg     = as.Date(fechas_pico_neg),
  peakdates_pos     = as.Date(fechas_pico_pos)
)
message("✔ [T-15] Índice global y fechas pico detectadas con peakdates().")

# 5. Fase 4: Modelado Econométrico Elastic Net y Atribuciones (T-17) ----

## 5.1 Serie mensual empírica real SIEDCO (alineada mes a mes con las noticias) ----
tasas_mensuales_distrito <- panel_delitos_mensual |>
  group_by(date_mes = as.Date(fecha_mes)) |>
  summarise(
    hurto_personas_total  = sum(hurto_personas, na.rm = TRUE),
    hurto_resid_total     = sum(hurto_residencias, na.rm = TRUE),
    hurto_motos_total     = sum(hurto_motos, na.rm = TRUE),
    hurto_total_denuncias = hurto_personas_total + hurto_resid_total + hurto_motos_total,
    poblacion_distrito    = sum(poblacion, na.rm = TRUE),
    y_tasa_hurto_mensual  = round((hurto_total_denuncias / poblacion_distrito) * 100000, 2),
    y_tasa_pers_mensual   = round((hurto_personas_total / poblacion_distrito) * 100000, 2),
    .groups               = "drop"
  ) |>
  arrange(date_mes)

fechas_esperadas_mes <- seq.Date(as.Date("2022-01-01"), as.Date("2026-09-01"), by = "month")
stopifnot(identical(tasas_mensuales_distrito$date_mes, fechas_esperadas_mes))

fechas_medidas     <- as.Date(sentometrics::get_dates(medidas_sento))
fechas_medidas_mes <- as.Date(format(fechas_medidas, "%Y-%m-01"))
stopifnot(all(fechas_medidas_mes %in% tasas_mensuales_distrito$date_mes))

serie_objetivo_mensual <- tibble(
  date     = fechas_medidas,
  date_mes = fechas_medidas_mes
) |>
  left_join(tasas_mensuales_distrito, by = "date_mes")

y_vector <- serie_objetivo_mensual$y_tasa_hurto_mensual
stopifnot(length(y_vector) == nrow(medidas_sento$measures))
stopifnot(all(!is.na(y_vector)))

## 5.2 Estimación de sento_model con penalización Elastic Net (h = 1 y contemporáneo) ----
control_modelo <- sentometrics::ctr_model(
  model        = "gaussian",
  type         = "BIC",
  alphas       = c(0.2, 0.5, 0.8),
  h            = 1,
  do.iter      = FALSE,
  do.progress  = FALSE
)

modelo_elasticnet <- sentometrics::sento_model(
  sento_measures = medidas_sento,
  y              = y_vector,
  ctr            = control_modelo
)

## 5.3 Cálculo de atribuciones multidimensionales (features, lexicons, time) ----
atribuciones_raw  <- sentometrics::attributions(
  model          = modelo_elasticnet,
  sento_measures = medidas_sento,
  do.lags        = TRUE,
  do.normalize   = FALSE
)

atribuciones_norm <- sentometrics::attributions(
  model          = modelo_elasticnet,
  sento_measures = medidas_sento,
  do.lags        = TRUE,
  do.normalize   = TRUE
)

# Extracción de valores ajustados y residuales para visualización en Shiny
n_total_m <- nrow(medidas_sento$measures)
idx_x     <- 1:(n_total_m - control_modelo$h)
idx_y     <- (1 + control_modelo$h):n_total_m

mat_x_alineada   <- as.matrix(medidas_sento$measures[idx_x, -1])
y_alineado       <- y_vector[idx_y]
fechas_alineadas <- fechas_medidas[idx_y]

pred_matriz <- as.numeric(predict(
  modelo_elasticnet,
  newx = mat_x_alineada
))

df_ajuste_modelo <- tibble(
  date       = fechas_alineadas,
  observado  = y_alineado,
  predicho   = round(pred_matriz, 2),
  residual   = round(y_alineado - pred_matriz, 2)
)

# Extracción de coeficientes distintos de cero
coefs_sparse <- coef(modelo_elasticnet$reg)
df_coeficientes <- tibble(
  variable    = rownames(coefs_sparse),
  coeficiente = as.numeric(coefs_sparse[, 1])
) |>
  filter(variable != "(Intercept)", abs(coeficiente) > 1e-8) |>
  arrange(desc(abs(coeficiente)))

# Formateo tidy de atribuciones para Plotly en Shiny
convertir_attr_long <- function(attr_obj, dimension) {
  dt_dim <- attr_obj[[dimension]]
  if (is.null(dt_dim)) return(tibble())
  as_tibble(dt_dim) |>
    mutate(date = as.Date(date)) |>
    pivot_longer(
      cols      = -date,
      names_to  = "componente",
      values_to = "atribucion"
    ) |>
    mutate(
      dimension        = dimension,
      componente_label = coalesce(unname(mapa_etiquetas_features[componente]), componente)
    )
}

df_attr_long_raw <- bind_rows(
  convertir_attr_long(atribuciones_raw, "features"),
  convertir_attr_long(atribuciones_raw, "lexicons"),
  convertir_attr_long(atribuciones_raw, "time")
)

df_attr_long_norm <- bind_rows(
  convertir_attr_long(atribuciones_norm, "features"),
  convertir_attr_long(atribuciones_norm, "lexicons"),
  convertir_attr_long(atribuciones_norm, "time")
)

# Validación fuera de muestra (do.iter = TRUE, nSample = 30 -> 21 pronósticos OOS) y benchmark AR(1)
control_modelo_oos <- sentometrics::ctr_model(
  model       = "gaussian",
  type        = "BIC",
  alphas      = c(0.2, 0.5, 0.8),
  h           = 1,
  do.iter     = TRUE,
  nSample     = 30,
  do.progress = FALSE
)
modelo_oos <- suppressWarnings(sentometrics::sento_model(
  sento_measures = medidas_sento,
  y              = y_vector,
  ctr            = control_modelo_oos
))
oos_real <- as.numeric(modelo_oos$performance$raw[, "response"])
ar1_preds_oos <- numeric(length(oos_real))
for (k in seq_along(oos_real)) {
  fin_tr <- 30L + k - 1L
  fit_ar1_k <- stats::lm(y_vector[2:fin_tr] ~ y_vector[1:(fin_tr - 1L)])
  ar1_preds_oos[k] <- stats::coef(fit_ar1_k)[1] + stats::coef(fit_ar1_k)[2] * y_vector[fin_tr]
}
rmse_oos_en  <- round(modelo_oos$performance$RMSFE, 3)
rmse_oos_ar1 <- round(sqrt(mean((oos_real - ar1_preds_oos)^2)), 3)

objeto_08_attributions <- list(
  modelo            = modelo_elasticnet,
  attributions_raw  = atribuciones_raw,
  attributions_norm = atribuciones_norm,
  attr_long_raw     = as.data.table(df_attr_long_raw),
  attr_long_norm    = as.data.table(df_attr_long_norm),
  ajuste_temporal   = df_ajuste_modelo,
  coeficientes      = df_coeficientes,
  metricas_modelo   = list(
    alpha_optimo          = modelo_elasticnet$alpha,
    lambda_optimo         = modelo_elasticnet$lambda,
    horizonte_h           = control_modelo$h,
    criterio              = control_modelo$type,
    r2_in_sample          = round(cor(df_ajuste_modelo$observado, df_ajuste_modelo$predicho)^2, 4),
    rmse                  = round(sqrt(mean(df_ajuste_modelo$residual^2)), 3),
    rmse_oos_en           = rmse_oos_en,
    rmse_oos_ar1          = rmse_oos_ar1,
    reduccion_rmse_vs_ar1 = round(100 * (rmse_oos_ar1 - rmse_oos_en) / rmse_oos_ar1, 1),
    n_observaciones       = nrow(df_ajuste_modelo),
    n_predictores         = sum(modelo_elasticnet$nVar),
    n_activos             = nrow(df_coeficientes)
  )
)

sentometrics_pipeline <- list(
  corpus_sento     = corpus_sento,
  lexicons_es      = lexicons_es,
  sentiment_scores = sentiment_scores,
  peak_docs        = objeto_04_peak_docs,
  sento_measures   = medidas_sento,
  measures_long    = objeto_06_measures_long,
  global_index     = objeto_07_global_index,
  attributions     = objeto_08_attributions,
  meta             = list(
    fecha_generacion       = Sys.time(),
    n_noticias_recopiladas = nrow(df_noticias),
    n_noticias_modelo      = nrow(df_noticias_enriquecida),
    modalidades_objetivo   = modalidades_objetivo_noticias,
    n_features             = length(cols_features),
    features               = cols_features,
    n_series               = ncol(medidas_sento$measures) - 1L
  )
)

archivo_pipeline_rds <- file.path(ruta_proc, "sentometrics_pipeline.rds")
saveRDS(sentometrics_pipeline, archivo_pipeline_rds)
message(
  "✔ [T-17] sentometrics_pipeline.rds guardado (36 series | Elastic Net alpha = ",
  modelo_elasticnet$alpha, ", R2 = ", objeto_08_attributions$metricas_modelo$r2_in_sample, ")."
)

# 6. Fase 5: Consolidación del Panel Anual Localidad × Año (2022–2026) ----

## 6.1 Agregación anual de sentimiento y cobertura por localidad ----
noticias_agg <- df_noticias_enriquecida |>
  filter(año >= 2022 & año <= 2026) |>
  group_by(localidad, año) |>
  summarise(
    noticias_conteo      = n(),
    noticias_dai_conteo  = sum(es_dai_estricto, na.rm = TRUE),
    sentimiento_promedio = round(mean(sentimiento_score, na.rm = TRUE), 4),
    sentimiento_nrc      = round(mean(score_nrc_es, na.rm = TRUE), 4),
    sentimiento_crimen   = round(mean(score_crimen_es, na.rm = TRUE), 4),
    sentimiento_mediana  = round(median(sentimiento_score, na.rm = TRUE), 4),
    prop_negativas       = round(mean(sentimiento_categoria == "Negativo", na.rm = TRUE) * 100, 2),
    prop_positivas       = round(mean(sentimiento_categoria == "Positivo", na.rm = TRUE) * 100, 2),
    prop_neutras         = round(mean(sentimiento_categoria == "Neutro", na.rm = TRUE) * 100, 2),
    .groups = "drop"
  )

## 6.2 Fusión con el panel delictivo y demográfico oficial ----
panel_consolidado <- panel_delitos |>
  left_join(noticias_agg, by = c("localidad", "año")) |>
  mutate(
    noticias_conteo      = replace_na(noticias_conteo, 0L),
    noticias_dai_conteo  = replace_na(noticias_dai_conteo, 0L),
    sentimiento_promedio = replace_na(sentimiento_promedio, 0),
    sentimiento_nrc      = replace_na(sentimiento_nrc, 0),
    sentimiento_crimen   = replace_na(sentimiento_crimen, 0),
    sentimiento_mediana  = replace_na(sentimiento_mediana, 0),
    prop_negativas       = replace_na(prop_negativas, 0),
    prop_positivas       = replace_na(prop_positivas, 0),
    prop_neutras         = replace_na(prop_neutras, 0)
  )

stopifnot(nrow(panel_consolidado) == 95)

archivo_panel_final <- file.path(ruta_proc, "panel_consolidado_localidad_anual.parquet")
arrow::write_parquet(panel_consolidado, archivo_panel_final)
message("✔ Panel consolidado anual guardado en: ", archivo_panel_final)
