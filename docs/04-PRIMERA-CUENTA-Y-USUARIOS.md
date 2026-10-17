# 04 — Primera cuenta, acceso y usuarios

> **Estado: no ejecutado.** No se creó ninguna cuenta real ni se probó el
> acceso. Este documento describe el procedimiento y lo que hay que verificar en
> el servidor.

**Rspamd no tiene usuarios de aplicación.** No hay registro, no hay base de
datos de cuentas, no hay "usuarios" en el sentido de una aplicación web.

Lo que tiene es:

- una **contraseña única** para la interfaz web de estadísticas
  (`worker controller`, puerto 11334);
- un **token** para el API HTTP de diagnóstico (puerto 11333), que se genera al
  crear el servicio;
- **ningún sistema de roles o permisos**.

Los usuarios de correo son del servidor de correo del cliente (Dovecot/Postfix),
**no de este kit**. Ver la advertencia del `README.md`.

---

## Procedimiento de primera cuenta

### Paso 1 — Confirmar que el servicio está sano

Antes de tocar contraseñas:

```bash
docker compose ps
docker compose exec rspamd rspamadm configtest
```

### Paso 2 — Generar el hash de la contraseña

```bash
docker compose exec rspamd rspamadm pw
```

Genera una contraseña al azar y muestra su hash con forma `$2$...`.

**La salida es la contraseña en forma hasheada.** El texto que sale de
`rspamadm pw` es lo que va en el archivo de configuración. Si pierde el texto,
tiene que generar otro.

### Paso 3 — Pegar el hash en la configuración

Edite `config/local.d/worker-controller.inc` y **descomente** la línea:

```
password = "<PEGAR_AQUI_EL_HASH>";
```

Este archivo está en `.gitignore`. **Nunca** se versiona.

### Paso 4 — Reiniciar y verificar

```bash
docker compose restart rspamd
docker compose ps    # debe volver a "healthy"
```

### Paso 5 — Probar el acceso por túnel SSH

**No abra el puerto 11334 en el firewall.** La interfaz web no tiene TLS: el
tráfico viaja en claro por la red.

Desde el equipo del técnico:

```bash
ssh -L 11334:127.0.0.1:11334 usuario@servidor-del-cliente
```

Después abra en el navegador:

```
http://localhost:11334
```

Ingrese la contraseña (el texto **original**, no el hash `$2$...`).

---

## Modelo de permisos: lo que existe y lo que no

| Aspecto | Situación real |
|---|---|
| Cuántas contraseñas | **Una**, para la interfaz web de estadísticas |
| Niveles de permiso | **Ninguno**. O se entra o no se entra. |
| Usuarios separados | **No hay.** El que entra ve las estadísticas completas. |
| Registro de auditoría de accesos | **No hay.** Rspamd no guarda quién entró ni cuándo. |
| Sesión expirada | Sí: por defecto una hora, ajustable con `sessions_expire`. |

**Consecuencia práctica para Hefesto:** si Hefesto da acceso al cliente, el
cliente ve **todo**: estadísticas, historial de mensajes y los controles de
ajustar puntajes. No hay forma de que el cliente vea "su parte" y Hefesto vea
"todo".

Si necesita dar a un cliente técnico **sin darle control**, el camino es dar
acceso al servidor por SSH y que use `rspamadm`, no darle la interfaz web.

---

## Cerrar el acceso anónimo

Mientras `worker-controller.inc` no tenga la línea `password` descomentada, la
interfaz web **no pide contraseña**. Solo está protegida por estar atada a
`127.0.0.1`.

**Regla para toda instalación:**

1. Siempre hay una contraseña, desde el primer minuto.
2. El puerto 11334 nunca se publica en el firewall.
3. Se accede siempre por túnel SSH.

## Endurecer el acceso

En `config/local.d/worker-controller.inc` ya viene:

```
secure_ip = ["127.0.0.0/8", "::1/128"];
```

Eso significa que solo se acepta conexión **sin contraseña** desde loopback. Si
alguien llega desde otra IP, se le pide contraseña incluso antes.

## Token del API HTTP (puerto 11333)

El puerto 11333 expone el API de diagnóstico. Cada worker genera un token
automáticamente al arrancar. Para consultarlo:

```bash
docker compose logs rspamd | grep -i token
```

### Un punto importante: `/ping` es distinto

El endpoint `/ping` del controller **siempre responde `pong` y nunca pide
contraseña**. Por eso el `healthcheck` del kit lo usa: si Rspamd está vivo,
responde `pong`.

No confundirse: que `/ping` responda **no significa que la interfaz tenga
contraseña puesta**. Son cosas distintas. El `healthcheck` solo verifica que el
proceso está vivo.

---

## Verificaciones

```bash
# El puerto no está abierto al mundo
ss -tlnp | grep 11334        # debe mostrar 127.0.0.1:11334, NO 0.0.0.0:11334

# El contenedor está sano
docker compose ps

# Rspamd responde
docker compose exec rspamd rspamadm configtest
```

**Regla de oro:** si `ss -tlnp` muestra `0.0.0.0:11334`, hay una configuración
incorrecta. El `compose.yaml` del kit publica ese puerto en `127.0.0.1`; si
aparece en todas las interfaces, alguien lo modificó o hay otro contenedor
publicando el mismo puerto.

---

## Lista para la entrega al cliente

- [ ] Contraseña de la interfaz web generada y puesta en `worker-controller.inc`.
- [ ] `worker-controller.inc` **no** está en git.
- [ ] El puerto 11334 no está abierto en el firewall.
- [ ] La interfaz se accede por túnel SSH y funciona.
- [ ] El cliente sabe que hay **una sola** contraseña, sin roles.
- [ ] El cliente sabe que **no hay registro de auditoría** de quién entró.
- [ ] El técnico tiene las credenciales del túnel SSH.