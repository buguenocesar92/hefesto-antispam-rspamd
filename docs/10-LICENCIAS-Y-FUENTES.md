# 10 — Licencias y fuentes

Este documento registra de dónde salió **cada** hecho técnico de este kit, para
que cualquiera pueda verificarlo sin confiar en Hefesto.

---

## 1. Licencia de cada componente

| Componente | Versión | Licencia | Fuente oficial |
|---|---|---|---|
| **Rspamd** | 4.2.2 | **Apache License 2.0** | [LICENSE.md](https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/LICENSE.md) |
| **Redis** | 8.10.2 | BSD de 3 cláusulas | [COPYING](https://github.com/redis/redis/blob/unstable/COPYING) |
| **ClamAV** | 1.5.4 | GPL-2.0 | [COPYING](https://github.com/Cisco-Talos/clamav/blob/main/COPYING) |
| **Docker Engine** | — | Apache 2.0 | [LICENSE](https://github.com/moby/moby/blob/master/LICENSE) |
| **Docker Compose** | — | Apache 2.0 | [LICENSE](https://github.com/docker/compose/blob/main/LICENSE) |

---

## 2. Rspamd es Apache 2.0 — el dato que más se corrige

**No es BSD.** Se verifica por tres vías independientes:

### Vía 1 — El archivo de licencia

<https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/LICENSE.md>

### Vía 2 — Las cabeceras del código fuente

Todos los archivos `.c` y `.cxx` del proyecto abren con el encabezado completo
de Apache 2.0. Ejemplo, `src/rspamd.c` de la etiqueta `4.2.2`:

```c
/*
 * Copyright 2024 Vsevolod Stakhov
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 * ...
 */
```

Fuente: <https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/src/rspamd.c>

### Vía 3 — La API de licencias de GitHub

<https://api.github.com/repos/rspamd/rspamd/license>

> **Matiz honesto:** esta API devuelve `"spdx_id": "NOASSERTION"`, **no**
> `"Apache-2.0"`. La razón es que el archivo se llama `LICENSE.md` y no
> `LICENSE`, y trae una línea de encabezado adicional. GitHub no logra
> detectarla automáticamente.
>
> El **texto** es el de Apache 2.0, y las cabeceras de los fuentes lo confirman
> sin ambigüedad. Quien lo cite como BSD está equivocado.

### Qué obliga Apache 2.0

- **Atribución:** indicar que se usa Rspamd.
- **Mantener** los avisos de copyright y las licencias originales.
- **Declarar** las modificaciones al código.
- **Permite uso comercial**, incluido cobrar por el servicio de puesta en
  marcha. No hay copyleft: **no obliga a publicar nada**.
- **Sin garantía:** se entrega "tal cual".

---

## 3. Fuentes de cada dato técnico del kit

Todo lo técnico de este kit sale de estas fuentes. Ninguna guía de terceros,
ningún artículo de blog.

### Versión y release

| Dato | Fuente |
|---|---|
| 4.2.2 es la última estable | `https://api.github.com/repos/rspamd/rspamd/releases/latest` |
| Release publicada el 2026-10-10 | <https://github.com/rspamd/rspamd/releases/tag/4.2.2> |

### Topología de workers

| Dato | Fuente |
|---|---|
| Workers `normal`, `controller`, `rspamd_proxy`, `fuzzy` | [`conf/rspamd.conf` en 4.2.2](https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/conf/rspamd.conf) |
| No existe `normalizer` | [`src/libserver` en 4.2.2](https://api.github.com/repos/rspamd/rspamd/contents/src/libserver?ref=4.2.2) — sin `normalizer.c` |
| No existe `vertstat` | El mismo listado — sin `vertstat.c` |
| `fuzzy` viene desactivado | `conf/rspamd.conf`: `count = -1` |

### Imagen de Docker

| Dato | Fuente |
|---|---|
| Puertos `EXPOSE`, usuario, volumen | [Dockerfile oficial](https://github.com/rspamd/rspamd-docker/blob/main/Dockerfile) |
| Healthcheck oficial | El mismo Dockerfile |
| Rutas de configuración | [Dockerfile.pkg](https://github.com/rspamd/rspamd-docker/blob/main/Dockerfile.pkg): `CONFDIR=/usr/share/rspamd/config`, `LOCALCONFDIR=/etc/rspamd` |
| Ejemplo oficial de Compose | [`examples/compose/compose.yaml`](https://github.com/rspamd/rspamd-docker/blob/main/examples/compose/compose.yaml) |

De ese ejemplo oficial sale el uso de `RSPAMD_REDIS_SERVERS`,
`RSPAMD_USE_BAYES`, `RSPAMD_USE_GREYLIST` y `RSPAMD_DNS_SERVERS`.

### Redis

| Dato | Fuente |
|---|---|
| Sin servidor Redis, bayes/greylist/rate limit quedan desactivados | <https://rspamd.com/>, sección "Connect Rspamd to Redis" |
| Sintaxis `servers = "..."` en `/etc/rspamd/local.d/redis.conf` | La misma sección |

### Módulos

| Módulo | Archivo fuente verificado |
|---|---|
| `antivirus` | [`src/plugins/lua/antivirus.lua`](https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/src/plugins/lua/antivirus.lua) |
| `dkim_signing` | [`src/plugins/lua/dkim_signing.lua`](https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/src/plugins/lua/dkim_signing.lua) |
| `whitelist` | [`src/plugins/lua/whitelist.lua`](https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/src/plugins/lua/whitelist.lua) |
| `greylist` | [`src/plugins/lua/greylist.lua`](https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/src/plugins/lua/greylist.lua) |

**Hallazgo que cambió la configuración del kit:** `check_pubkey = true` en
`dkim_signing` consulta el registro TXT `<selector>._domainkey.<dominio>` y
**no firma** si no existe. Viene en `false` por defecto; el kit lo pone en
`true`. Ver `config/local.d/dkim_signing.conf`.

### Integración con Postfix

| Dato | Fuente |
|---|---|
| `smtpd_milters = inet:localhost:11332`, `milter_protocol = 6` | <https://rspamd.com/>, sección de integración |

### Digests de imagen

| Imagen | Fuente |
|---|---|
| `rspamd/rspamd:4.2.2` | [Docker Hub, listado de etiquetas](https://hub.docker.com/v2/repositories/rspamd/rspamd/tags) |
| `redis:8.10.2` | <https://hub.docker.com/v2/repositories/library/redis/tags> |
| `clamav/clamav:1.5.4` | <https://hub.docker.com/v2/repositories/clamav/clamav/tags> |

Los valores están anotados en `VERSION.md`.

---

## 4. Lo que NO está verificado

Transparencia: esto queda documentado porque el contrato del estudio lo exige.

| Dato | Estado |
|---|---|
| Sintaxis exacta de `rspamadm dkim_keygen` | **Pendiente.** El conjunto de comandos de `rspamadm` no se pudo listar del código en 4.2.2. |
| Comportamiento de `compose.yaml` en ejecución | **Pendiente.** No hay Docker en el entorno donde se preparó. |
| Consumo real de RAM de ClamAV | **Pendiente.** La cifra de 1 a 2 GB es la documentada habitualmente, no medida en este kit. |
| Versiones de Postfix y Dovecot compatibles | **Pendiente.** El kit trae ejemplos, no configuración probada contra una versión concreta. |

Cada uno de estos está marcado como pendiente en el documento que lo usa y en
`docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## 5. Attribution

Si en algún momento se redistribuye parte de este kit (por ejemplo, una
imagen con Rspamd adentro), **hay que mantener los avisos de copyright y las
licencias originales**.

Apache 2.0 no obliga a abrir el código propio de quien lo usa, pero sí obliga a
no quitar los avisos de los componentes de terceros.

Texto sugerido para material del cliente:

> El filtrado de correo de este servicio utiliza **Rspamd**, un proyecto de
> código abierto bajo **licencia Apache 2.0** (<https://github.com/rspamd/rspamd>).
> La instalación, configuración y soporte son provistos por Hefesto Studio.

---

## 6. Marcas

- **Rspamd** es marca de sus autores. Hefesto Studio la usa solo para identificar
  el componente técnico.
- **Redis** es marca de Redis Ltd. También aplica el aviso de BSD.
- **ClamAV** es marca de Cisco Talos.

No use los logotipos de estos proyectos en material comercial de Hefesto.

---

## Cómo verificar este documento

Todo lo anterior se puede comprobar sin instalar nada:

```bash
# Versión de Rspamd
curl -s https://api.github.com/repos/rspamd/rspamd/releases/latest | grep tag_name

# Licencia
curl -s https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/LICENSE.md | head -5

# Topología de workers
curl -s https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/conf/rspamd.conf | grep -A2 '^worker'

# Que no existe normalizer ni vertstat
curl -s https://api.github.com/repos/rspamd/rspamd/contents/src/libserver?ref=4.2.2 \
  | grep -E 'normalizer|vertstat'    # No debe devolver nada

# Opciones del módulo antivirus
curl -s https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/src/plugins/lua/antivirus.lua \
  | grep -E 'servers|max_size|log_clean'

# Digests
docker buildx imagetools inspect rspamd/rspamd:4.2.2
```

Si alguno de estos comandos no da lo que dice este documento, **el documento
está mal y hay que corregirlo**. Preferimos eso a una cita de segunda mano.