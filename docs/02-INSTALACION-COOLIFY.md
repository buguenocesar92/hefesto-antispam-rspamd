# 02 — Instalación en Coolify

> **Estado: no ejecutado.** No se probó este kit en Coolify. Lo que sigue se
> basa en cómo funciona un recurso "Docker Compose" de Coolify y en las
> restricciones reales de este kit, que **no son pocas**.

---

## Recomendación honesta: no use Coolify para este kit

**Recomendamos instalar este kit con `docker compose` directo**
(`docs/01-INSTALACION-DOCKER.md`), no como recurso de Coolify.

Rspamd **no es una aplicación web**. No tiene dominio, ni puerto HTTP público,
ni certificado, ni usuarios de una base de datos. Es un **milter**: un servicio
al que el servidor de correo del cliente le entrega cada mensaje ya recibido,
por un puerto local.

Coolify está pensado para exponer aplicaciones por HTTP/HTTPS detrás de un proxy.
Acá casi nada de eso aplica, y(forzarlo introduce riesgos que no vale la pena
pagar:

| Lo que Coolify haría | Por qué es un problema |
|---|---|
| Exponer la interfaz web con dominio y HTTPS | La interfaz **solo** debearse por túnel SSH. Publicarla agrupa la superficie de ataque sin necesidad. |
| Terminar TLS en el proxy | El tráfico entre el proxy y Rspamd quedaría en HTTP plano dentro del servidor. |
| Gestionar reinicios y healthchecks | Coolify los administra, pero Rspamd depende de que Redis esté sano **antes**, y eso no lo expresa bien un `depends_on` de Coolify. |
| Recargar variables al desplegar | Un reinicio de Coolify en pleno Filtering deja el correo sin filtrar o acumulado. |

Si el cliente **ya tiene Coolify** y todo su stack vive ahí, igual es preferible
desplegar Rspamd aparte con `docker compose`. Rspamd no comparte nada con el
resto: ni base de datos, ni red, ni dominio.

---

## Si de todas formas se quiere usar Coolify

Documentado para que quede registro de la decisión, **no como recomendación**.

### Qué crear

Recurso de tipo **Docker Compose**, apuntando al directorio del kit.

### Configuración

| Campo | Valor | Nota |
|---|---|---|
| Compose file | `compose.yaml` | El del kit, sin modificar |
| Variables de entorno | Las de `.env.example` | Subir como variables del recurso |
| Puertos | **Ninguno** hacia Internet | Ver más abajo |
| Dominio | **Ninguno** | Rspamd no se expone por dominio |
| Volúmenes | Los tres nombrados del compose | Coolify los administra |
| Healthcheck | Los que ya vienen en el compose | No reemplazarlos |

### Sobre los puertos: lo que hay que hacer

El `compose.yaml` del kit pública tres puertos **atados a `127.0.0.1`**, lo que
significa que **no son accesibles desde fuera** del servidor. Eso es
intencional.

Si Coolify pública esos puertos por su cuenta, deja de estar atado a loopback y
queda accesible desde Internet. Eso **no se debe hacer**. En Coolify, deje los
puertos sinDominio asociado.

Si necesitaReachgar la interfaz web, hágalo por **túnel SSH**, no por dominio:

```bash
ssh -L 11334:127.0.0.1:11334 usuario@servidor
```

### El perfil de ClamAV

ClamAV está detrás del perfil `antivirus`. En Coolify, para activarlo hay que
levantar el recurso **con el perfil**, lo que en la interfaz se traduce en
agregar el perfil al comando de despliegue. Si no sabe cómo se hace en su
versión de Coolify, **no lo active desde Coolify**: instale el kit con
`docker compose` directo.

### Lo que se pierde al usar Coolify

- Los scripts de respaldo asumen que se opera desde el directorio del kit con
  `docker compose`. Con Coolify hay que revisar `scripts/backup-rspamd.sh` antes
  de usarlo: los contenedores pueden no tener los nombres esperados.
- La verificación de rutas y la comprobación de destinos ocupados de
  `restore-rspamd.sh` asumen acceso al `docker compose` del directorio. Con
  Coolify hay que adaptar los comandos.

**Por eso el orden es: pruebe los scripts con `docker compose` directo.**

---

## Alternativa recomendada si el cliente insiste en Coolify

Instale Rspamd con `docker compose` en el mismo servidor donde corre Coolify,
pero **fuera de Coolify**:

- Un servicio systemd simple que ejecute `docker compose up -d` y lo mantenga.
- Los puertos quedan atados a `127.0.0.1` igual que en la instalación directa.
- Los scripts de respaldo funcionan sin cambios.

Si necesita que un cambio de configuración de Rspamd se despliegue desde
Coolify, use Coolify para el **resto** del stack del cliente y este kit por
fuera. No mezcle.

---

## Verificación

```bash
# Desde el servidor
docker compose ps
docker compose exec rspamd rspamadm configtest
```

Si en Coolify:

```bash
docker ps | grep -i rspamd
docker exec <contenedor_rspamd> rspamadm configtest
```

La lista completa de comprobaciones, y qué está verificado y qué no, está en
`docs/07-PRUEBAS-DE-ACEPTACION.md`.