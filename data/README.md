# Organización de los datos

En esta carpeta guardamos los datos del proyecto, separando claramente lo que bajamos de internet de lo que nosotros mismos procesamos y limpiamos.

---

## 1. Estructura de las carpetas de datos

```text
data/
├── raw/                              # Datos tal como bajan de las fuentes oficiales (sin tocar)
│   ├── delitos_alto_impacto_raw.parquet # Hurtos registrados vía API de Socrata (SDSCJ)
│   ├── poblacion_localidades_raw.parquet# Habitantes por localidad 2005-2035 (SDS)
│   ├── localidades_bogota_raw.geojson  # Mapas y polígonos de las localidades (SDP)
│   ├── noticias_google_news_consolidado.parquet # Base final de noticias validadas
│   └── noticias/                     # Particionado de noticias guardadas mes por mes
│       └── chunk_*.parquet           # Lotes mensuales por localidad
└── processed/                        # Datos listos y normalizados para los modelos y gráficos
    ├── tasas_hurtos_localidad.parquet# Tasas de hurto calculadas por cada 100.000 habitantes
    ├── sentimiento_noticias.parquet  # Puntuaciones de sentimiento de sentometrics
    ├── clusters_localidades.parquet  # Perfiles de inseguridad calculados con K-means
    └── datos_consolidados_shiny.rds  # Archivo único listo para que la app Shiny lo lea
```

---

## 2. Fuentes oficiales que usamos

| Conjunto de datos | Entidad que lo publica | Cómo lo obtenemos | Formato en que lo guardamos |
| :--- | :--- | :--- | :--- |
| **Delitos de Alto Impacto** | Secretaría de Seguridad (SDSCJ / SIEDCO) | API de Socrata con filtros SQL | `.parquet` |
| **Proyecciones de Población** | Secretaría de Salud (SDS) | Portal de Datos Abiertos de Bogotá | `.parquet` |
| **Mapas de las Localidades** | Secretaría de Planeación (SDP) | Portal de Datos Abiertos de Bogotá | `.geojson` y `.parquet` |
| **Noticias de Prensa** | Google Noticias | Web Scraping con Selenium | `.parquet` |

---

## 3. Manejo de archivos en Git
* Los archivos muy pesados (mayores a 50MB) o temporales no se suben a Git para no saturar el repositorio. Están excluidos en `.gitignore`.
* Mantenemos las carpetas visibles en Git usando archivos `.gitkeep`.
* Si clonas el repositorio y quieres recrear todas las bases de `data/processed/`, solo tienes que correr `scripts/master.R`.
