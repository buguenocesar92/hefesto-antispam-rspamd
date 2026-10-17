# 01 — Instalación con Docker (Ubuntu/Debian)

Procedimiento paso a paso desde un servidor Ubuntu o Debian limpio, con los
comandos exactos.

> **Estado: no ejecutado.** Este procedimiento está escrito a partir de la
> documentación oficial de Rspamd y del Dockerfile oficial, pero **no se corrió
> en un servidor real** durante la preparación del kit. Cada paso tiene su
> comando de verificación: úselos a medida que avanza, no al final.

---

## Antes de empezar: ¿este cliente necesita este kit?

Acepte el trabajo solo si el cliente cumple **las dos** condiciones:

- [ ] Tiene **servidor de correo propio** (Postfix, Dovecot, Exim, Courier…).
- [ ] Tiene **control sobre los registros DNS** de su dominio.

Si usa Google Workspace, Microsoft 365, Zoho, Mailchimp u otro servicio
gestionado, **este kit no le sirve**. Ya hay un filtro instalado y no se puede
poner Rspamd delante sin romper el servicio. Dígalo antes de cobrar.

Si tiene servidor de correo pero **no** control del DNS, se puede instalar
Rspamd, pero **sin DKIM saliente**. La firma necesita un registro TXT que solo
puede publicar quien administra la zona.

---

## 1. Requisitos del servidor

| Recurso | Con el kit básico | Con antivirus (perfil `antivirus`) |
|---|---|---|
| RAM | 2 GB | **4 GB mínimo, 8 GB recomendado** |
| CPU | 2 núcleos | 2 núcleos |
| Disco | 10 GB | 20 GB (las firmas de ClamAV pesan) |

ClamAV carga todas sus firmas **en memoria** al arrancar: entre 1 GB y 2 GB. Si
el servidor no tiene ese margen, no lo active. El antivirus es opcional.

## 2. Instalar Docker

En Ubuntu/Debian actual, Docker Engine y su plugin de Compose se instalan desde
el repositorio oficial de Docker, no desde el paquete del sistema.

```bash
# Repositorio oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
     -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
                        docker-buildx-plugin docker-compose-plugin
```

> En Debian, cambie `ubuntu` por `debian` en las dos primeras líneas.

**Verificar:**

```bash
sudo docker --version
sudo docker compose version
```

## 3. Poner el directorio del kit en el servidor

Por ejemplo, con `scp` o `rsync`:

```bash
sudo mkdir -p /opt/hefesto
sudo chown "$USER" /opt/hefesto
rsync -av ./hefesto-antispam-rspamd/ usuario@servidor:/opt/hefesto/
```

Luego, en el servidor:

```bash
cd /opt/hefesto/hefesto-antispam-rspamd
```

## 4. Crear el archivo de variables

```bash
cp .env.example .env
nano .env
```

Revise, como mínimo:

| Variable | Qué revisar |
|---|---|
| `TZ` | `America/Santiago` si el servidor está en Chile |
| `RSPAMD_DNS_SERVERS` | Resolutor DNS. Ver más abajo. |
| `RSPAMD_USE_GREYLIST` | Ponga `0` la primera semana. Ver más abajo. |
| `RSPAMD_MILTER_PORT` | Debe coincidir con `smtpd_milters` en Postfix |

### Sobre `RSPAMD_DNS_SERVERS`

Rspamd consulta listas negras (RBL) por DNS. **Muchos RBL rechazan o bloquean
las consultas que llegan directo desde IPs de centro de datos.** Si el servidor
está en un datacenter, es probable que necesite un **resolutor DNS local
recursivo** (por ejemplo Unbound) en vez del del host.

Este kit **no incluye** Unbound a propósito: su configuración depende mucho de
cada red y una mal configurada rompe todas las listas negras. Si deja la
variable vacía, Rspamd usa el valor por defecto de la imagen oficial.

Revise `docs/03-VARIABLES-Y-COMO-OBTENERLAS.md` para el detalle.

### Sobre el greylisting: los primeros días

`RSPAMD_USE_GREYLIST=0` durante los primeros 3 a 7 días.

El greylisting retiene el primer correo de un remitente nuevo. Es la capa que
más falsos positivos genera y la que más llamadas produce en la primera semana.
Con la lista blanca bien cargada primero, después se activa.

Ver `config/local.d/greylist.conf` y la sección "Plan de las primeras dos
semanas" del `README.md`.

## 5. Levantar

```bash
docker compose up -d
```

**Verificar:**

```bash
docker compose ps
```

Todos los servicios deberían mostrar `healthy`. Si alguno muestra
`unhealthy` o `starting` demasiado tiempo:

```bash
docker compose logs --tail=50 rspamd
docker compose logs --tail=50 redis
```

## 6. Verificar la configuración de Rspamd

Este es el paso que más se saltea. `rspamadm configtest` valida la
configuración **sin** poner nada en producción.

```bash
docker compose exec rspamd rspamadm configtest
```

Debe responder sin errores. Si hay un error de sintaxis, revise
`docker compose logs rspamd`: ahí sale el archivo y la línea.

## 7. Ponerle contraseña a la interfaz web

Mientras no se haga esto, la interfaz web **no tiene contraseña**. Está atada
a `127.0.0.1`, así que no es accesible desde Internet, pero hay que ponerle
contraseña antes de entregarla.

```bash
docker compose exec rspamd rspamadm pw
```

Copie la salida (empieza con `$2$`) a
`config/local.d/worker-controller.inc` y **descomente la línea**:

```
password = "<PEGAR_AQUI>";
```

```bash
docker compose restart rspamd
```

> `worker-controller.inc` está en `.gitignore` porque contiene un secreto.

### Nota de seguridad de Rspamd 4.2.2

En la versión 4.2.2, el controller **rechaza la contraseña por defecto** cuando
alguien se conecta a través de un puerto publicado. Aun así, hasta que se
defina una propia, la interfaz queda sin contraseña real.

## 8. Instalar la interfaz DKIM (opcional pero recomendado)

Antes de firmar correo saliente:

1. Genere el par de claves en el servidor (comando **pendiente de verificar**).
2. Publique la clave pública como registro TXT `dkim._domainkey`.
3. Active el módulo en `config/local.d/dkim_signing.conf`.

Procedimiento completo en `ejemplos/dkim-y-dns.demostracion.md`.

## 9. Conectar Postfix

Solo después de que los pasos 5, 6 y 7 estén bien.

Copie las líneas de `ejemplos/postfix-main.cf.demostracion` a la configuración
de Postfix. La línea crítica:

```
smtpd_milters = inet:127.0.0.1:11332
non_smtpd_milters = inet:127.0.0.1:11332
milter_default_action = tempfail
```

Aplique en horario de baja carga y tenga el procedimiento de reversión a mano.

**Verificar:**

```bash
postconf -n | grep milter
postfix reload
docker compose logs -f rspamd     # debe recibir mensajes
```

## 10. Cargar la lista blanca

Antes de recibir correo real, con la lista blanca de los clientes y
proveedores conocidos:

```
# config/local.d/whitelist.conf
whitelist {
  rules {
    WHITELIST_CLIENTE_1 {
      priority = 1;
      domains = ["ejemplo.cl"];
      score = 2.0;
    }
  }
}
```

```bash
docker compose restart rspamd
```

**Este paso es la diferencia entre una primera semana tranquila y una semana de
llamadas.** Ver `README.md` → "Rspamd no es perfecto".

## 11. Primer respaldo

Hágalo antes de tocar nada del cliente:

```bash
sudo ./scripts/backup-rspamd.sh
```

Ver `docs/05-RESPALDOS-Y-RESTAURACION.md`.

---

## Comprobación final

```bash
docker compose ps                      # todo "healthy"
docker compose exec rspamd rspamadm configtest   # sin errores
docker compose logs --tail=50 rspamd   # sin errores de configuración
```

El checklist completo, con lo verificado y lo pendiente, está en
`docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## Diferencias con Coolify

La instalación en Coolify está en `docs/02-INSTALACION-COOLIFY.md`. La
diferencia de fondo: aquí se opera con `docker compose` directamente; allá,
Coolify administra los contenedores.

**Una diferencia que importa mucho:** Rspamd **no debe exponerse por HTTPS a
través de un proxy inverso**. La interfaz web está en HTTP plano y sin TLS. Si
se pone detrás de un proxy con HTTPS, Hefesto queda como responsable de la
exposición. Ver `docs/02-INSTALACION-COOLIFY.md`.