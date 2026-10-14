# Estructura y Gestión de Datos

Esta carpeta organiza los datos del proyecto garantizando trazabilidad desde las fuentes públicas originales hasta los artefactos analíticos finales.

---

## 1. Directorios

```text
data/
├── raw/                              # Microdatos crudos descargados de fuentes oficiales
│   ├── delitos_alto_impacto_raw.parquet # Hurtos extraídos vía API Socrata (SDSCJ)
│   ├── poblacion_localidades_raw.parquet# Proyecciones demográficas 2005-2035 (SDS)
│   ├── localidades_bogota_raw.geojson  # Cartografía oficial de localidades (SDP)
│   ├── noticias_google_news_consolidado.parquet # Base de noticias validadas
│   └── noticias/                     # Particionado mensual de scraping con checkpointing
│       └── chunk_*.parquet           # Micro-lotes mensuales por localidad
└── processed/                        # Datos limpios y normalizados para modelado
    ├── tasas_hurtos_localidad.parquet# Tasas delictivas por 100k hab. (2022-2025)
    ├── sentimiento_noticias.parquet  # Puntuaciones de polaridad sentometrics
    ├── clusters_localidades.parquet  # Perfiles no supervisados K-means
    └── datos_consolidados_shiny.rds  # Dataset integrado consumido por Shiny
```

---

## 2. Fuentes Oficiales

| Conjunto de Datos | Entidad Emisora | Acceso / Protocolo | Formato Local |
| :--- | :--- | :--- | :--- |
| **Delitos de Alto Impacto** | Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ / SIEDCO) | API Socrata SoQL / Datos Abiertos Bogotá | `.parquet` |
| **Proyecciones de Población** | Secretaría Distrital de Salud (SDS) | Datos Abiertos Bogotá (Pirámide 2005–2035) | `.parquet` |
| **Límites de Localidades** | Secretaría Distrital de Planeación (SDP) | Datos Abiertos Bogotá | `.geojson` / `.parquet` |
| **Prensa sobre Inseguridad** | Google News | Web Scraping automatizado (`RSelenium`) | `.parquet` |

---

## 3. Política de Versionamiento
* Los archivos pesados o temporales de gran tamaño se encuentran excluidos en `.gitignore`.
* Se preserva la estructura de carpetas vacías mediante archivos `.gitkeep`.
* Toda base contenida en `data/processed/` es 100% reproducible ejecutando `scripts/master.R`.
