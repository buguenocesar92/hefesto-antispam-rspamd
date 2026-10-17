# 07 — Pruebas de aceptación

> **Este documento separa lo que se verificó de lo que no.**
> No presente lo pendiente como si estuviera hecho.

---

## Resumen honesto

| Categoría | Cantidad |
|---|---|
| Verificado contra fuente oficial | 8 áreas |
| Verificado localmente (sintaxis) | 3 archivos |
| **Pendiente: requiere un servidor** | **10 ítems** |

**El kit NO ha corrido.** No se ejecutó `docker compose up`. No se recibió
correo. No se midió la tasa de falsos positivos.

El estado del kit es **`kit preparado`**, según la definición del contrato del
estudio.

---

# PARTE 1 — Lo que SÍ se verificó

## 1.1 Versión exacta de Rspamd — VERIFICADO

**Resultado: 4.2.2**, etiqueta `4.2.2`, publicada el **2026-10-10**.

Cómo se verificó:

```bash
curl -s https://api.github.com/repos/rspamd/rspamd/releases/latest
```

Devolvió `"tag_name": "4.2.2"`, `"prerelease": false`,
`"published_at": "2026-10-10T14:03:32Z"`.

Fuente: <https://github.com/rspamd/rspamd/releases/tag/4.2.2>

**No se copió el número de ninguna guía de terceros.**

## 1.2 Licencia — VERIFICADO

**Apache License 2.0. No BSD.**

Tres fuentes independientes:

1. `LICENSE.md` del repositorio, etiqueta `4.2.2`:
   <https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/LICENSE.md>
2. Cabeceras de los archivos fuente: todos abren con el encabezado completo de
   Apache 2.0.
3. Perfil oficial de Docker Hub de `rspamd/rspamd`.

Fuente de la API de licencias de GitHub: <https://api.github.com/repos/rspamd/rspamd/license>

> Matiz honesto: esa API devuelve `NOASSERTION` porque el archivo se llama
> `LICENSE.md` y trae una línea de encabezado adicional. El **texto** es Apache
> 2.0 y las cabeceras de los fuentes lo confirman.

## 1.3 Topología real de workers en 4.2.2 — VERIFICADO

Leído del archivo de configuración **de la versión exacta**:

<https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/conf/rspamd.conf>

| Worker | Puerto |
|---|---|
| `normal` | 11333 |
| `controller` | 11334 |
| `rspamd_proxy` | 11332 |
| `fuzzy` | 11335 (desactivado: `count = -1`) |

**Correcciones importantes:**

- **No existe `normalizer`.** El directorio `src/libserver` de 4.2.2 no tiene
  `normalizer.c`.
- **No existe `vertstat`.** Tampoco hay `vertstat.c` en 4.2.2.
- **No hay worker `dkim` separado.** La firma la hace el módulo `dkim_signing`.

Fuente: <https://api.github.com/repos/rspamd/rspamd/contents/src/libserver?ref=4.2.2>

## 1.4 Redis: obligatorio en este kit, y por qué — VERIFICADO

La afirmación "Rspamd no arranca sin Redis" es **inexacta** para la versión
actual.

La documentación oficial dice que la configuración de fábrica **no trae
servidor Redis definido** y que **Bayes, greylisting y rate limiting quedan
desactivados** hasta que se agregue uno.

Fuente: <https://rspamd.com/> — sección "Connect Rspamd to Redis".

Configuración usada, según la misma fuente:

```
# /etc/rspamd/local.d/redis.conf
servers = "redis:6379";
```

**Por qué el kit lo exige igual:** porque el fallo es silencioso. Sin Redis,
Rspamd arranca, la interfaz se ve bien, y faltan las tres capas que más spam
filtran. En el kit Redis es obligatorio y tiene `healthcheck`.

## 1.5 Puertos de la imagen oficial — VERIFICADO

Del `Dockerfile` oficial de `rspamd/rspamd-docker`:
<https://github.com/rspamd/rspamd-docker/blob/main/Dockerfile>

- `EXPOSE 11332 11332; 11333 normal; 11334 controller`
- `USER 11333:11333` (no root)
- `VOLUME /var/lib/rspamd`
- `ENV RSPAMD_LOCAL_ADDR=*` y `RSPAMD_LOG_TYPE=console`

**Rspamd NO expone puertos SMTP.** Por eso el kit no publica ninguno.

## 1.6 Healthcheck — VERIFICADO

El `Dockerfile` oficial trae un `HEALTHCHECK` propio. El `compose.yaml` del kit
lo **copia tal cual**: consulta `/ping` en el puerto del controller y busca
`pong`.

```bash
exec 3<>/dev/tcp/127.0.0.1/11334
printf "GET /ping HTTP/1.0\r\n\r\n" >&3
grep -q pong <&3
```

`/ping` nunca pide contraseña: por eso sirve como verificación de vida.

## 1.7 Opciones de los módulos — VERIFICADO

Leídas del código fuente de la etiqueta `4.2.2`:

| Módulo | Archivo | Datos confirmados |
|---|---|---|
| `antivirus` | `src/plugins/lua/antivirus.lua` | `servers` (por defecto `127.0.0.1:3310`), `max_size` (20 MB), `log_clean`, `symbol_fail` |
| `dkim_signing` | `src/plugins/lua/dkim_signing.lua` | `selector` (por defecto `dkim`), `path` (`$DBDIR/dkim/$domain.$selector.key`), `sign_authenticated`, `sign_local`, `check_pubkey`, `allow_username_mismatch`, `allow_hdrfrom_mismatch` |
| `whitelist` | `src/plugins/lua/whitelist.lua` | `rules`, `domains`, `score`, `blacklist`, `strict`, `inverse_symbol`, `check_local`, `check_authed`, `dmarc_allow_symbol`, `spf_allow_symbol`, `dkim_allow_symbol` |
| `greylist` | `src/plugins/lua/greylist.lua` | `expire`, `timeout`, `redis_timeout`, `key_prefix` (por defecto `rg`), `max_data_len`, `symbol` |

### Un hallazgo que cambió la configuración de este kit

`check_pubkey = true` en `dkim_signing` hace que Rspamd **consulte el registro
TXT `<selector>._domainkey.<dominio>` antes de firmar** y, si no existe, **no
firme**, dejándolo asentado en el registro.

Es el ajuste que evita "firmo con una clave que nadie conoce". Viene en `false`
por defecto; el kit lo pone en `true`. Ver `config/local.d/dkim_signing.conf`.

## 1.8 Digests de imagen — VERIFICADO

Consultados en Docker Hub:

| Imagen | Digest de índice |
|---|---|
| `rspamd/rspamd:4.2.2` | `sha256:33526f94cfbb5ab5485805ad9d6eddb6a52aca6529aad0ce99b67b01c2e756de` |
| `redis:8.10.2` | `sha256:2c2dff791878316e3b083188be0d578423b24813cdda5de0e80ea4f7b3e6bfd6` |
| `clamav/clamav:1.5.4` | `sha256:638d90201ee7ee6a82d249a2fc23b132e578673b5f1f2766852b127676ca1ef6` |

Además se confirmó que `latest` de Rspamd apuntaba a un digest **distinto** del
de `4.2.2`, lo que justifica la fijación por etiqueta.

## 1.9 Verificación local de sintaxis — EJECUTADO

Esto **sí** se ejecutó en la máquina donde se preparó el kit:

| Archivo | Comprobación | Resultado |
|---|---|---|
| `compose.yaml` | Parseo como YAML (`yaml.safe_load`) | **Correcto** |
| `scripts/backup-rspamd.sh` | `bash -n` (análisis sintáctico) | **Correcto** |
| `scripts/restore-rspamd.sh` | `bash -n` | **Correcto** |

Y una revisión de todos los archivos para detectar caracteres fuera del
español (CJK, cirílico), en dos pasadas.

> Esto verifica **sintaxis**, no comportamiento. Un script puede estar
> sintácticamente perfecto y fallar en ejecución.

---

# PARTE 2 — Lo que está PENDIENTE

Nada de esta sección se ejecutó. **No se presente como probado.**

| # | Qué falta | Por qué | Cómo se verifica |
|---|---|---|---|
| 1 | Que `compose.yaml` levante los servicios | No hay Docker en este entorno | `docker compose up -d` y `docker compose ps` |
| 2 | Que los healthchecks pasen | No se levantó nada | `docker compose ps` debe mostrar `healthy` |
| 3 | `rspamadm configtest` sin errores | No hay contenedor | `docker compose exec rspamd rspamadm configtest` |
| 4 | La sintaxis exacta de `rspamadm dkim_keygen` | Los comandos de `rspamadm` no se pudieron listar del código | `docker compose exec rspamd rspamadm dkim_keygen --help` |
| 5 | Firma DKIM de punta a punta | Requiere DNS real y un verificador externo | Enviar correo y revisar cabeceras + un validador DKIM |
| 6 | Medir la tasa real de falsos positivos | Requiere correo real de un cliente | La interfaz web y el API HTTP de diagnóstico |
| 7 | Respaldo y restauración completos | No se ejecutaron los scripts | Ver `docs/05-RESPALDOS-Y-RESTAURACION.md` |
| 8 | Configuración de Postfix con la versión del cliente | Cada cliente tiene una versión distinta | `postconf -n` y envío de prueba |
| 9 | Configuración de Dovecot | Sin servidor con Dovecot | `doveconf -n` debe mostrar las claves aplicadas |
| 10 | Consumo real de RAM con ClamAV | No se midió | `docker stats` con el perfil antivirus activo |

## 2.1 Cómo medir los falsos positivos

**Es la pregunta que todo cliente hace en la primera semana.** Y no se puede
responder sin medir.

### La cifra honesta

Rspamd **no entrega una tasa de falsos positivos garantizada**, y no existe una
cifra universal: depende del volumen de correo del cliente, de la calidad de su
lista blanca inicial, y de si el greylisting está activo.

### Cómo se mide en la práctica

**Paso 1 — La interfaz web.**

```bash
ssh -L 11334:127.0.0.1:11334 usuario@servidor
```

La sección de **historial** muestra los mensajes rechazados. Ahí están los
falsos positivos que el cliente está reclamando.

**Paso 2 — Contar lo que el cliente reclama.**

La métrica que importa no es un porcentaje, es la lista concreta:

| Semana | Correos legítimos perdidos | Remitentes afectados | Agregados a la lista blanca |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Esa tabla, en tres semanas, es la que se le entrega al cliente. Es honesta y
es accionable.

**Paso 3 — El API HTTP de diagnóstico.**

Para consultar un mensaje específico:

```bash
curl --data-binary @correo.eml http://127.0.0.1:11333/checkv2
```

Devuelve los símbolos y la decisión que habría tomado el filtro. Sirve para
**auditar un caso concreto**, no para estadísticas.

> El puerto 11333 usa un token. Para obtenerlo:
> `docker compose logs rspamd | grep -i token`

### El número de referencia que sí se puede dar

**No se puede dar un porcentaje.** Lo que sí se puede afirmar, y con respaldo:

- Al partir de una lista blanca bien cargada y con greylisting apagado, el
  número de reclamos en la primera semana **depende de qué tan completa esté
  esa lista**, no del filtro.
- El filtro se comporta de forma distinta en cada cliente. Medir en un cliente
  no dice nada del otro.

**Nunca prometa un porcentaje.** Prometa el proceso: lista blanca, medición
semanal y reversión rápida.

### Entrenamiento de bayes

Desde la interfaz web, el cliente puede marcar mensajes como **legítimos** o
como **basura**. Eso alimenta el clasificador.

Con pocos mensajes, bayes **no aporta nada**: necesita cientos para ser útil.
No lo prometa como una función: recién empieza a servir tras semanas de uso real.

## 2.2 Flujo de reversión manual de un falso positivo

Cuando el cliente avisa que no llegó un correo:

```
1. Identificar el remitente
2. Revisar el historial en la interfaz web (puerto 11334, por túnel SSH)
3. Agregar el dominio a config/local.d/whitelist.conf
4. docker compose restart rspamd
5. Avisar al cliente que ya quedó
6. Anotarlo en la tabla de la sección 2.1
```

Tiempo típico: **menos de 10 minutos**.

Si además se perdió un correo importante, el cliente puede pedir que se reenvíe.
Verificar primero que **no esté en la cola de Postfix**: con
`milter_default_action = tempfail`, los mensajes rechazados por Rspamd **no se
descartan**, quedan en cola y se reintentan. Eso es un buen motivo para usar
`tempfail` y no `discard`.

## 2.3 Checklist de aceptación en un servidor real

Para usar en la primera instalación:

**Infraestructura**

- [ ] `docker compose up -d` sin errores
- [ ] `docker compose ps` muestra los servicios en `healthy`
- [ ] `ss -tlnp` muestra los puertos de Rspamd solo en `127.0.0.1`
- [ ] El puerto 6379 de Redis **no** aparece publicado

**Configuración**

- [ ] `rspamadm configtest` responde sin errores
- [ ] `docker compose logs rspamd` sin errores de configuración
- [ ] `redis-cli ping` responde `PONG`

**Filtro**

- [ ] Llega correo legítimo de un cliente conocido
- [ ] El spam de prueba no pasa
- [ ] El correo de un cliente de la lista blanca nunca es descartado
- [ ] Las cabeceras de Rspamd aparecen en un correo recibido

**DKIM**

- [ ] El registro TXT `dkim._domainkey.<dominio>` responde con `dig`
- [ ] El correo saliente trae la cabecera `DKIM-Signature`
- [ ] Un validador externo dice `pass`

**Respaldo**

- [ ] `backup-rspamd.sh` genera un archivo
- [ ] `sha256sum -c` da correcto
- [ ] Se restauró una copia en un servidor de prueba

---

## Resumen para el comercial

**Se puede afirmar:**

- Versiones exactas y verificadas contra fuente oficial.
- Licencia verificada (Apache 2.0).
- Topología de la versión 4.2.2 verificada leyendo su código.
- Scripts de respaldo que verifican lo que hacen.

**No se puede afirmar:**

- Que el kit esté instalado y funcionando.
- Una tasa de falsos positivos.
- Compatibilidad con una versión específica de Postfix o Dovecot.

**El kit está en estado `kit preparado`.** El primer despliegue en un servidor
real es lo que lo mueve a `validado localmente`.