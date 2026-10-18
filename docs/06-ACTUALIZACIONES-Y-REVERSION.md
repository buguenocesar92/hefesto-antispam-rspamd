# 06 — Actualizaciones y reversión

> **Estado: no ejecutado.** No se actualizó ninguna instalación. Este documento
> describe el procedimiento y sus riesgos.

---

## La regla que no se negocia

**Nunca actualice Rspamd sin respaldo previo, en horario de baja carga, y
sin haber confirmado que la versión destino existe y es estable.**

Rspamd actualiza con frecuencia. Las versiones mayores cambian comportamiento
(no de configuración, pero sí de clasificación y de módulos). Una actualización
puede cambiar sutilmente la puntuación de un mensaje que antes pasaba.

---

## Antes de actualizar

### 1. Confirmar la versión destino

```bash
# Ver la última release estable publicada
curl -s https://api.github.com/repos/rspamd/rspamd/releases/latest \
  | grep -E '"tag_name"|"prerelease"'
```

La release debe tener `"prerelease": false`. Si es `true`, es una versión de
pruebas: **no la instale en producción**.

### 2. Leer las notas de la versión

<https://github.com/rspamd/rspamd/releases>

Busque, en orden de importancia:

- ¿Cambia algún módulo que usamos? (`antivirus`, `dkim_signing`, `whitelist`,
  `greylist`).
- ¿Cambia el formato de los archivos de bayes o de las claves DKIM?
- ¿Cambia el formato del dump de Redis?
- ¿Saca algún worker o puerto? (pasó con `normalizer` y `vertstat` en versiones
  anteriores).

### 3. Respaldo

```bash
cd /opt/hefesto/hefesto-antispam-rspamd
sudo ./scripts/backup-rspamd.sh
```

Sin este paso, no siga.

### 4. Anotar la versión actual

```bash
docker compose exec rspamd rspamd --version
docker compose config | grep image
```

Con esas dos líneas se puede volver atrás exactamente.

---

## Actualizar

### Rspamd

```bash
# 1. Ver qué se actualizará
docker compose pull rspamd

# 2. Revisar el cambio en compose.yaml (debe ser SOLO la etiqueta)
#    Editar:  image: rspamd/rspamd:4.2.2  ->  image: rspamd/rspamd:<NUEVA>

# 3. Levantar
docker compose up -d rspamd

# 4. Verificar
docker compose ps                        # "healthy"
docker compose exec rspamd rspamadm configtest
docker compose logs --tail=50 rspamd
```

### Redis

```bash
docker compose pull redis
# Editar la etiqueta en compose.yaml
docker compose up -d redis
docker compose exec redis redis-cli ping    # PONG
```

Redis se puede actualizar por partes: si está caído unos segundos, Rspamd sigue
funcionando con lo que tiene en memoria.

### ClamAV

```bash
docker compose --profile antivirus pull clamav
docker compose --profile antivirus up -d clamav
```

Después de actualizar ClamAV, **esperar a que cargue las firmas**. Puede tardar
varios minutos. Mientras carga, el healthcheck queda `starting`, y con
`symbol_fail` configurado, Rspamd rechaza el correo.

> Para evitarlo, actualice ClamAV en una ventana en la que no entre correo, o
> deje el antivirus desactivado mientras actualiza.

---

## Reversión

Si algo salió mal, volver a la versión anterior.

### Rspamd

```bash
# 1. Volver a la versión anterior en compose.yaml
#    Editar:  image: rspamd/rspamd:<NUEVA>  ->  image: rspamd/rspamd:4.2.2

# 2. Levantar la anterior
docker compose up -d rspamd

# 3. Verificar
docker compose ps
docker compose exec rspamd rspamadm configtest
```

### Redis

Idéntico: cambiar la etiqueta y `docker compose up -d redis`.

### Si la reversión no basta

El problema no es la versión, son los datos. Restarurar un respaldo:

```bash
sudo ./scripts/restore-rspamd.sh --archivo respaldos/rspamd-<fecha>.tar.gz
```

Recuerde: el script deja el servicio **detenido** al terminar, a propósito.

---

## Qué migraciones NO son reversibles

Esta es la parte que hay que leer con atención antes de actualizar.

### Datos de bayes y caché de hyperscan

Al **bajar** de versión, los archivos de bayes o de cache pueden estar en un
formato que la versión anterior no sabe leer. La síntoma típico es que Rspamd
avisa y **regenera** el cache: el filtro sigue funcionando, pero pierde parte
del aprendizaje.

**Consecuencia:** si actualiza 4.2.2 → 4.3.0 y después vuelve atrás, es posible
que necesite **entrenar de nuevo** el filtro.

**Antes de actualizar, anote la lista blanca.** Esa es la que más cuesta
reconstruir.

### Claves DKIM

Las claves **no se migran** al bajar de versión: la clave privada sigue ahí,
pero si el formato cambió, Rspamd no la encuentra.

**Antes de actualizar, copie `/var/lib/rspamd/dkim/` a un lugar seguro.**

### Formato del dump de Redis

Al bajar de versión, un `dump.rdb` escrito por una versión más nueva puede no
ser legible. Redis se niega a arrancar y avisa en el log.

**Este es el motivo de la advertencia siguiente.**

---

## [IMPORTANTE] La actualización de Redis tiene un riesgo real

**Bajar de versión de Redis con un dump nuevo puede dejar Redis sin arrancar.**

Procedimiento seguro:

1. **Haga una copia del dump ANTES de actualizar.** Justo eso evita la pérdida
   de datos bayes y greylist.
2. Si Redis no arranca con la versión antigua, no intente arreglarlo a mano.
   Restaure el dump desde el respaldo.

El respaldo del kit cubre esto: `scripts/backup-rspamd.sh` incluye el
`dump.rdb` de Redis.

---

## Reglas operativas

1. **Una actualización por vez.** No actualice Rspamd, Redis y ClamAV el mismo
   día. Si algo falla, no se va a saber qué fue.
2. **En horario de baja carga**, y avise al cliente.
3. **Respaldo antes de cada una.**
4. **Verifique el healthcheck** antes de dar por buena la actualización.
5. **Anote la versión anterior** en el registro de cambios del cliente.
6. **Espere al menos 24 horas** antes de actualizar a la siguiente versión. Rspamd
   pública versiones con frecuencia; no es buena idea seguirle el ritmo en un
   servidor de correo de una Pyme.
7. **Si una versión le genera dudas, no la instale.** Una versión estable menos
   reciente es mejor que una reciente con problemas.