# 03 — Variables de entorno y cómo obtenerlas

Todas las variables del kit, de dónde sale cada una y qué pasa si se cambia
después de instalar.

---

## Tabla general

| Variable | ¿Obligatoria? | Ejemplo | De dónde sale | Qué pasa si se cambia después |
|---|---|---|---|---|
| `RSPAMD_MILTER_PORT` | **Sí** | `11332` | Lo decide Hefesto. Debe coincidir con `smtpd_milters` de Postfix. | Postfix sigue apuntando al puerto viejo. Si cambia el del host, hay que cambiar Postfix **y reiniciarlo**, o el correo deja de filtrarse en silencio. |
| `RSPAMD_CONTROLLER_PORT` | **Sí** | `11334` | Lo decide Hefesto. | Solo cambia dónde se conecta el túnel SSH. Sin impacto en el correo. |
| `RSPAMD_HTTP_PORT` | No | `11333` | Lo decide Hefesto. | Solo afecta al diagnóstico por `curl`. |
| `RSPAMD_DNS_SERVERS` | **Sí** | vacío | Ver sección abajo. | Hay que reiniciar Rspamd. Cambiar mal deja las listas negras sin respuesta, y el filtro pasa spam sin avisar. |
| `RSPAMD_USE_BAYES` | **Sí** | `1` | Decisión de Hefesto en la reunión de inicio. | Requiere reiniciar. Si se apaga, el clasificador deja de aprender. |
| `RSPAMD_USE_GREYLIST` | **Sí** | `1` o `0` | Decisión de Hefesto. Recomendado `0` la primera semana. | Requiere reiniciar. Si se cambia `key_prefix` en otro lado, se pierde el historial (ver `greylist.conf`). |
| `CLAMAV_MEMSIZE` | No | `2g` | Según la RAM del servidor del cliente. | Requiere recrear el contenedor. Si se queda corto, clamd muere al cargar firmas. |
| `CLAMAV_FRESHCLAMD_CHECKS` | No | `1` | Decisión de Hefesto. | Requiere recrear el contenedor. |
| `TZ` | **Sí** | `America/Santiago` | Zona horaria del cliente. | Requiere recrear el contenedor. Sin esto los registros quedan en UTC. |

---

## Variables que administra el kit (no se editan)

Estas están fijadas en `compose.yaml` a propósito, para que coincidan con los
nombres de servicio de la red de Docker:

| Variable | Valor fijo | Por qué |
|---|---|---|
| `RSPAMD_REDIS_SERVERS` | `redis` | Es el nombre del servicio de Redis en Compose. Cambiarlo rompe la conexión. |

Y una que **no va en `.env`**:

| Dónde | Qué es |
|---|---|
| `config/local.d/worker-controller.inc` | El **hash** de la contraseña de la interfaz web. |

Esa contraseña **no** es una variable de entorno. Se genera con el binario de
Rspamd, no con `openssl`:

```bash
docker compose exec rspamd rspamadm pw
```

La salida tiene forma `$2$...` y va en ese archivo, que está en `.gitignore`
porque es un secreto.

---

## `RSPAMD_DNS_SERVERS`: la variable que más se mal configura

### Para qué sirve

Rspamd consulta **listas negras de correo (RBL)** por DNS. Para eso necesita un
resolutor DNS.

### El problema real

Muchos RBL —Spamhaus entre ellos— **rechazan o bloquean las consultas que
llegan directo desde IPs de centro de datos**. Un servidor en un datacenter
puede obtener respuesta vacía o de rechazo, y Rspamd cree que esa lista negra no
tiene entradas.

**El síntoma es silencioso y peligroso**: el filtro sigue funcionando, la
interfaz se ve bien, y simplemente no está bloqueando ninguna IP de las listas.
El spam entra.

### Las tres opciones

**Opción A — Resolutor local recursivo (recomendada en datacenter).**
Instale Unbound en el host y apunte Rspamd a él. Se pueden agregar más
resolutores después en la configuración del contenedor.

**Opción B — El resolver del host.**

```
RSPAMD_DNS_SERVERS=round-robin:172.17.0.1:53
```

La IP depende de la red. Fijela con `172.17.0.1` solo si `docker network
inspect` de la red del kit muestra esa puerta de enlace.

**Opción C — Dejarlo vacío.**

```bash
RSPAMD_DNS_SERVERS=
```

Rspamd usa el valor por defecto de la imagen oficial. **Válido**, pero en un
servidor de datacenter es probable que las listas negras no respondan.

### Cómo saber si las listas negras funcionan

Envíe correo de prueba desde una IP que esté en una lista negra conocida y
revise qué símbolos agrega Rspamd en el registro:

```bash
docker compose logs -f rspamd
```

Si **no aparece ningún símbolo de lista negra** cuando debería, es casi seguro
un problema de DNS.

---

## `CLAMAV_MEMSIZE`: por qué el antivirus es opcional

ClamAV carga el conjunto completo de firmas de virus **en memoria** al arrancar.
Una instancia normal usa **entre 1 GB y 2 GB**.

Si se pone el límite muy bajo, el proceso de clamd puede ser terminado por el
kernel durante la carga de firmas. El síntoma es un contenedor que entra en
crash loop y un antivirus que en realidad no está escaneando nada.

Por eso:

- ClamAV está **detrás del perfil `antivirus`** y no arranca por defecto.
- `CLAMAV_MEMSIZE=2g` es una **decisión consciente de Hefesto**, no un valor
  de upstream. Está anotada como tal en `compose.yaml`.
- El `README.md` dice que con antivirus el servidor necesita 4 GB como mínimo.

Si el servidor no tiene la memoria, **no active el antivirus**. Rspamd filtra
muy bien sin él.

---

## Cómo se cambian las variables

Las variables de `.env` **no** se leen en caliente. Después de editarlas:

```bash
# Recreate: necesario si cambió una variable de entorno del contenedor
docker compose up -d --force-recreate rspamd

# Verificar que tomó la nueva configuración
docker compose exec rspamd rspamadm configtest
docker compose exec rspamd env | grep RSPAMD_
```

Un `docker compose restart` **no** basta si cambió una variable de entorno:
`restart` reinicia el mismo contenedor, que conserva las variables old.

---

## Comprobación de que Redis está realmente conectado

Redis ausente es un fallo **silencioso**. Rspamd arranca igual, pero quedan
apagados bayes, greylisting y rate limiting.

```bash
# 1. Redis responde
docker compose exec redis redis-cli ping
# Debe responder: PONG

# 2. Rspamd tiene claves de bayes (con el tiempo aparece al menos una)
docker compose exec redis redis-cli --scan --pattern 'b*' | head

# 3. Rspamd reporta Redis en su propio estado
docker compose exec rspamd rspamadm configtest
```

Si `redis-cli ping` no responde, Redis está caído y Rspamd está funcionando a
medio gas.

---

## Error frecuente: cambiar `RSPAMD_MILTER_PORT` y olvidar Postfix

Si cambia el puerto del host, tiene que cambiar también Postfix **antes** de
reiniciar, o el correo deja de pasar por el filtro:

```
smtpd_milters = inet:127.0.0.1:<PUERTO_NUEVO>
```

Y después `postfix reload`.

La forma segura es dejar `11332` como está. No hay razón para cambiarlo.