# 09 — Exportación y traspaso

> **Estado: no ejecutado.** No se exportó nada desde una instalación real. Los
> formatos y comandos de este documento están derivados de la estructura
> verificada del kit, pero **no se comprobaron en un servidor**.

---

## Advertencia honesta sobre "exportar los datos"

Este kit **no guarda los correos de los usuarios**. Eso es del servidor de
correo del cliente (Postfix/Dovecot).

Lo que sí se puede exportar son tres cosas:

| Qué | Dónde vive | Para qué |
|---|---|---|
| **Aprendizaje bayesiano** | Volumen `rspamd-data` | No perder lo aprendido |
| **Lista blanca y configuración** | `config/local.d/` | Documentar o replicar la configuración |
| **Estadísticas** | Interfaz web, puerto 11334 | Reporte al cliente |

**No hay "exportar datos" en el sentido de una aplicación con base de datos.**
Rspamd no tiene base de datos relacional.

---

## 1. Exportar la configuración

Es lo más simple y lo más importante.

```bash
# La configuración son archivos de texto
tar -czf config-rspamd-<fecha>.tar.gz config/local.d/
```

**Cuidado:** ese archivo contiene el hash de la contraseña de la interfaz web.
Trátelo como secreto.

Si quiere exportar la configuración **sin** el secreto:

```bash
tar -czf config-sin-secreto-<fecha>.tar.gz \
    config/local.d/redis.conf \
    config/local.d/dkim_signing.conf \
    config/local.d/whitelist.conf \
    config/local.d/greylist.conf \
    config/local.d/antivirus.conf
```

---

## 2. Exportar el aprendizaje bayesiano

No hay comando de exportación de bayes: son **archivos** en el volumen.

```bash
# El volumen vive en el sistema, no en el directorio del kit
sudo docker run --rm \
    -v hefesto-antispam-rspamd_rspamd-data:/datos:ro \
    -v "$PWD":/salida \
    debian:bookworm-slim \
    tar -czf /salida/bayes-<fecha>.tar.gz -C /datos .
```

**En la práctica, no haga esto.** Use `scripts/backup-rspamd.sh`, que ya hace
todo esto correctamente: detiene Rspamd, fuerza el guardado de Redis, calcula
los SHA-256 y escribe el manifiesto.

```bash
sudo ./scripts/backup-rspamd.sh
```

---

## 3. Exportar estadísticas

### Desde la interfaz web

Por túnel SSH a `http://localhost:11334`. Desde ahí se pueden revisar y
descargar las estadísticas.

> La interfaz web **no tiene API documentada para exportación masiva** que se
> haya verificado en este kit. No se documenta aquí ningún endpoint que no se
> haya comprobado.

### Desde los registros

```bash
# Un día completo de registro
docker compose logs --since 24h rspamd > registros-rspamd-<fecha>.txt
```

### Desde Redis

```bash
# Cuántos clasificadores hay
docker compose exec redis redis-cli --scan | wc -l

# Claves de greylist
docker compose exec redis redis-cli --scan --pattern 'rg*' | wc -l
```

---

## 4. Traspaso a otra persona o a otro proveedor

### Si traspasa a otro técnico de Hefesto

1. Entregue el directorio del kit con `config/local.d/` completo.
2. Entregue los respaldos más recientes, **cifrados**.
3. Entregue la contraseña de la interfaz web.
4. Entregue el acceso SSH del servidor.
5. Entregue el acceso al panel DNS del dominio.

Y deje por escrito:
- la versión instalada de Rspamd y Redis (`docker compose ps`);
- dónde está la lista blanca y qué significa cada regla;
- qué remitentes se agregaron por reclamo, y por qué.

### Si traspasa a un cliente que lo administrará solo

| Qué entregar | Por qué |
|---|---|
| Acceso SSH al servidor | Único acceso real: por `docker compose` |
| Acceso al panel DNS | Para publicar los registros DKIM cuando rotar claves |
| Contraseña de la interfaz web | Para ver estadísticas |
| Este kit, con los respaldos | Para no depender de Hefesto |

**Y tenga una conversación franca:** sin alguien que mire la lista blanca cada
semana, la calidad del filtro se degrada en dos o tres meses. El sistema no se
mantiene solo.

---

## 5. Traspaso a Odoo u otra plataforma

> **El contrato del estudio exige distinguir el conector verificado de la
> sincronización automática. aquí no hay ninguna de las dos.**

### Lo que ocurre realmente

**Rspamd no tiene conector a Odoo, ni a ningún otro ERP o CRM.** No existe
integración oficial, ni de Hefesto, ni de terceros.

### Lo que sí se puede hacer

**Integración indirecta, vía correo:**

Rspamd opera sobre el flujo SMTP. Si el cliente usa Odoo, el flujo sigue siendo
correo, y Rspamd sigue funcionando **igual**, porque no sabe ni le importa que
la otra ponta sea Odoo.

```
Remitente  ->  [servidor de correo del cliente]  ->  Rspamd  ->  Buzón del usuario
                                                          |
Odoo envía correo por SMTP, igual que cualquier otro programa.
No requiere ninguna configuración especial en Rspamd.
```

**Caveat importante:** si el cliente usa el **servicio de correo de Odoo**
(Odoo Online o Enterprise con el addon de correo), el flujo **no pasa por el
servidor del cliente** y Rspamd no interviene.

### Tabla de verdad

| Integración | ¿Existe? | Detalle |
|---|---|---|
| Rspamd → Odoo | **No** | Sin conector |
| Rspamd → ERP/CRM | **No** | Sin conector |
| Rspamd → API de terceros | **No** | Sin conector |
| Rspamd filtrando el correo que Odoo envía | **Sí** | Por SMTP, sin configuración especial |
| Rspamd filtrando el correo que Odoo Online **recibe** | **No** | Si usa el correo de Odoo, no pasa por el servidor del cliente |
| Sincronización automática de datos | **No** | No hay nada que sincronizar: Rspamd no guarda datos de negocio |

### Lo que NO es cierto

- **No** existe "el conector de Odoo" de Hefesto.
- **No** se importan contactos de Odoo a Rspamd.
- **No** hay reportes automáticos hacia Odoo.
- **No** hay sincronización de nada.

---

## 6. Traslado a otro servidor

Es una operación real y soportada por el kit:

```bash
# 1. En el servidor viejo
cd /opt/hefesto/hefesto-antispam-rspamd
sudo ./scripts/backup-rspamd.sh

# 2. Copiar el directorio del kit y el .tar.gz al servidor nuevo
rsync -av . usuario@servidor-nuevo:/opt/hefesto/

# 3. En el servidor nuevo: restaurar
cd /opt/hefesto/hefesto-antispam-rspamd
sudo ./scripts/restore-rspamd.sh \
     --archivo respaldos/rspamd-<fecha>.tar.gz \
     --force --sin-config

# 4. Revisar el dominio antes de arrancar
#    Si cambió la IP, el SPF y el DKIM hay que actualizarlos.

# 5. Arrancar y verificar
docker compose start rspamd redis
docker compose ps
```

### Lo que hay que revisar en un traslado

| Punto | Por qué |
|---|---|
| **IP del servidor** | Si cambió, hay que actualizar el registro SPF y los registros A/MX. |
| **Claves DKIM** | El respaldo las trae, pero hay que confirmar que el DNS publica la clave correcta. |
| **Zona horaria** | Revisar `TZ` en el `.env` nuevo. |
| **Lista blanca** | Confirmar que sigue completa para el cliente. |

**El DNS es lo que más se olvida en un traslado**, y es lo que hace que el
cliente deje de recibir o de enviar correo. Revíselo antes de cortar producción.

---

## Resumen

| Se puede | No se puede |
|---|---|
| Exportar la configuración a `.tar.gz` | Exportar los correos (este kit no los guarda) |
| Respaldar y restaurar el aprendizaje | Exportar "datos de negocio" (no hay) |
| Descargar estadísticas desde la interfaz web | Usar un endpoint de exportación no verificado |
| Exportar los registros de texto | Sincronizar con Odoo o cualquier ERP |
| Trasladar el kit a otro servidor | Suponer que el correo de Odoo Online pasa por Rspamd |
| Integrar por SMTP sin tocar nada | Integración directa con Odoo: **no existe** |