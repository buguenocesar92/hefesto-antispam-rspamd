# Versiones y origen de cada componente

Este kit fija **versiones exactas**. Nada usa `latest`.

Las fechas de abajo son las que se observaron al armar este kit. Antes de
desplegar en un cliente nuevo, conviene volver a confirmar que la versión
sigue siendo la estable vigente.

---

## Componentes del kit

| Componente | Versión fijada | Fecha de publicación | Origen de la versión |
|---|---|---|---|
| Rspamd | **4.2.2** | 2026-10-10 | GitHub Releases, etiqueta `4.2.2` |
| Redis | **8.10.2** | — | Docker Hub, etiqueta `8.10.2` |
| ClamAV (imagen) | **1.5.4** | — | Docker Hub, etiqueta `1.5.4` |

### Fuente de la versión de Rspamd

- Repositorio: <https://github.com/rspamd/rspamd>
- Release: <https://github.com/rspamd/rspamd/releases/tag/4.2.2>
- Se consultó `https://api.github.com/repos/rspamd/rspamd/releases/latest`, que
  devolvió `"tag_name": "4.2.2"` y `"published_at": "2026-10-10T14:03:32Z"`.
  Esa es la release marcada como no-prerelease.

**No se copiaron números de versión de guías de terceros.** El número salió de
la API de releases del propio proyecto.

---

## Imágenes de contenedor

Digests de índice (multi-arquitectura), observados al armar el kit:

| Imagen | Referencia | Digest de índice |
|---|---|---|
| Rspamd | `rspamd/rspamd:4.2.2` | `sha256:33526f94cfbb5ab5485805ad9d6eddb6a52aca6529aad0ce99b67b01c2e756de` |
| Redis | `redis:8.10.2` | `sha256:2c2dff791878316e3b083188be0d578423b24813cdda5de0e80ea4f7b3e6bfd6` |
| ClamAV | `clamav/clamav:1.5.4` | `sha256:638d90201ee7ee6a82d249a2fc23b132e578673b5f1f2766852b127676ca1ef6` |

Digest específico de **linux/amd64** para Rspamd 4.2.2:
`sha256:de03754f20092364a93bc4b91a051eea5ae54b0a5b04e61df383afc2ce04a29d`

### Por qué el kit NO pone el digest en el `compose.yaml`

`compose.yaml` fija la **etiqueta de versión**, que ya es una versión fija. El
digest queda anotado acá como endurecimiento opcional.

Motivo práctico: si alguien pega el digest en el `compose.yaml` y el registro
reconstruye la imagen multi-arquitectura para otra plataforma, el digest puede
quedar desactualizado y el despliegue falla con un error poco intuitivo. Con la
etiqueta fija, un despliegue en otra arquitectura funciona igual.

Para fijar por digest en su servidor, agregue el digest a la referencia y
verifique primero que coincide:

```bash
# Ver el digest real de la imagen fijada
docker buildx imagetools inspect rspamd/rspamd:4.2.2

# Después, en compose.yaml:
#   image: rspamd/rspamd:4.2.2@sha256:33526f94...
```

### Razón concreta para no usar `latest` aquí

Al consultar Docker Hub, la etiqueta `latest` de Rspamd apuntaba a un digest
**distinto** del de `4.2.2`:

- `latest` → `sha256:04aa2490165acbe1678d2bcab081be3c0bec39c0b12f0bcc4780329d32a3cf69`
- `4.2.2` → `sha256:33526f94cfbb5ab5485805ad9d6eddb6a52aca6529aad0ce99b67b01c2e756de`

Es decir, `latest` ya había cambiado respecto de la release 4.2.2. Con
`latest`, dos servidores instalados el mismo día pueden estar corriendo código
distinto. Eso es exactamente lo que un servicio de seguridad para Pymes no
puede darse.

---

## Topología de servicios que exige Rspamd 4.2.2

Este punto se verificó leyendo el archivo de configuración de la propia versión,
no una guía de terceros:
<https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/conf/rspamd.conf>

Los **workers** en 4.2.2 son:

| Worker | Puerto | Para qué sirve |
|---|---|---|
| `normal` | 11333 | Procesamiento normal y API HTTP de diagnóstico |
| `controller` | 11334 | Interfaz web y API de administración |
| `rspamd_proxy` | 11332 | **Milter**: recibe aquí los mensajes desde el MTA |
| `fuzzy` | 11335 | Almacenamiento local difuso. Viene **desactivado** por defecto (`count = -1`) |

### Corrección importante sobre la topología histórica

Mucha documentación antigua —y Kits actuales— describen Rspamd como un grupo de
servicios separados: `rspamd`, `rspamd-vertstat`, `controller`, `worker`,
`normalizer`, `dkim`. **Esa topología no aplica hoy.**

Verificado en el código de la versión 4.2.2:

- **No existe el worker `normalizer`.** El directorio `src/libserver` de la
  etiqueta `4.2.2` no tiene `normalizer.c`.
- **No existe el worker `vertstat`.** Tampoco hay `vertstat.c` en 4.2.2.
- **No hay un worker `dkim` separado.** La firma DKIM la hace el módulo
  `dkim_signing`; no es un worker con puerto propio.

Los cuatro workers de la tabla viven **dentro del mismo contenedor**, todos en
el mismo proceso. El kit despliega **un solo servicio `rspamd`**, igual que el
ejemplo oficial de `rspamd-docker`.

El contenedor `worker-hs_helper` es opcional y solo aparece si Rspamd se compiló
con Hyperscan. No se despliega.

---

## Topología de contenedores del kit

| Servicio | Imagen | Cuándo arranca |
|---|---|---|
| `redis` | `redis:8.10.2` | Siempre |
| `rspamd` | `rspamd/rspamd:4.2.2` | Siempre |
| `clamav` | `clamav/clamav:1.5.4` | Solo con el perfil `antivirus` |

Redis va siempre. Ver la sección siguiente.

---

## Redis: obligatorio en este kit, y por qué

Existe una afirmación muy repetida de que "Rspamd no arranca sin Redis". **No
es exacta para la versión actual.**

La documentación oficial dice lo contrario: la configuración que viene de
fábrica **no trae servidor Redis definido**, y Rspamd **arranca igual**. Lo que
queda apagado son tres cosas:

- el clasificador **bayesiano**,
- el **greylisting**,
- el **rate limiting**.

Texto de la documentación oficial (sección "Connect Rspamd to Redis"):

> "The shipped configuration has no Redis server set, so Bayes, greylisting and
> rate limiting stay disabled until you add one"

> Traducción: "La configuración incluida no tiene servidor Redis definido, así
> que Bayes, el greylisting y el rate limiting quedan desactivados hasta que
> agregues uno".

### Por qué entonces Redis es obligatorio en este kit

Porque el fallo es **silencioso**. Rspamd levanta, la interfaz web se ve bien,
el servicio "está funcionando", y en realidad faltan las tres capas que más
spam filtran y más falsos positivos evitan. El cliente descubriría el problema
cuando empiece a caer correo legítimo, que es el peor momento.

En el kit, Redis es servicio obligatorio y además tiene `healthcheck`, de modo
que la ausencia se ve en `docker compose ps` en vez de descubrirse en producción.

Configuración usada:

- Variable oficial `RSPAMD_REDIS_SERVERS` (usada en el ejemplo oficial de
  `rspamd-docker`).
- `config/local.d/redis.conf` con `servers = "redis:6379";`, que es la sintaxis
  que muestra la documentación oficial.

---

## ClamAV

- Módulo de Rspamd: `antivirus` (el archivo del módulo se llama `antivirus.lua`).
- Puerto por defecto de `clamd`: **3310**.
- No se pública en el host: solo se habla por la red interna de Docker.

Las **firmas de ClamAV sí se redescargan solas** cuando arranca `clamav`. Por
eso no se respaldan (ver `docs/05-RESPALDOS-Y-RESTAURACION.md`).

---

## Licencias

Ver `LICENCIAS.md` y `docs/10-LICENCIAS-Y-FUENTES.md`.

Resumen: **Rspamd es Apache License 2.0**, no BSD. Quien cite "BSD" en una
propuesta comercial está equivocado.