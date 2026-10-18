# Kit de despliegue de Rspamd — Hefesto Studio

Servicio de seguridad de correo para Pymes que tienen su propio dominio y hoy
usan un filtro limitado o directamente ninguno.

---

## [IMPORTANTE] Lee esto antes de contratar nada

### 1. Rspamd no es un servidor de correo

**Este kit no sirve para un cliente que no tenga servidor de correo propio.**

Rspamd es **el filtro**, no el servidor de correo. El correo entra primero al
servidor de correo del cliente —Postfix, Dovecot o lo que use— y desde ahí se le
entrega a Rspamd para que lo evalúe.

Para que este kit sirva, el cliente debe cumplir **las dos** condiciones:

- tiene **servidor de correo propio** (o una instancia dedicada, no un
  servicio compartido como el correo de Google Workspace o Microsoft 365); y
- tiene **control sobre sus registros DNS** del dominio, porque la firma DKIM
  y la reputación IP dependen de ellos.

Si el cliente usa Google Workspace, Microsoft 365, Zoho o similar, **este kit no
le sirve**: ya tiene su propio filtrado, el de Google o el de Microsoft, y Rspamd
no se puede poner delante de forma útil sin romper el servicio.

Si el cliente no tiene servidor de correo, la alternativa correcta es que
Hefesto le ofrezca **construirlo** o le recomiende su proveedor de correo
gestionado. Este kit es solo una pieza de esa solución.

> La composición completa de un servicio de correo para Pymes es:
> servidor de correo (Postfix/Dovecot) + Rspamd + DNS bien configurado.
> Este kit entrega la pieza del medio.

### 2. No es antispam perfecto: va a descartar correo legítimo

**No existe un filtro de correo electrónico que no Tire correo bueno.** Cualquier
proveedor que prometa "cero falsos positivos" está mintiendo.

Cuando el filtro descarta un correo que era de verdad, para el cliente es un
correo perdido. Si ese correo era una factura, un pedido o un mensaje de un
cliente, es un **problema de negocio**, no un detalle técnico.

Por eso el kit trae, y hay que usar:

- **Lista blanca** (`config/local.d/whitelist.conf`): los remitentes de fiar
  entran sin ser evaluados. Con eso no pueden ser descartados.
- **Aprendizaje bayesiano**: el filtro aprende de lo que el usuario marque como
  legitimo o basura.
- **Reversión manual**: cómo recuperar un correo descartado por error.
- **Medición de falsos positivos**: cómo detectarlos antes de que llame el
  cliente.

Todo eso está explicado en `docs/07-PRUEBAS-DE-ACEPTACION.md` y en
`README.md` → sección "Rspamd no es perfecto" más abajo.

La primera semana es la más delicada. Avise al cliente.

### 3. ClamAV es pesado en memoria

Si se activa el antivirus, el servidor necesita **entre 2 GB y 4 GB de RAM
libres** además de lo demás. Ver requisitos abajo.

---

## Estado del kit

```
kit preparado
```

**Archivos escritos. Docker no ejecutado. Ningún servidor desplegado.**

Este kit **no** ha corrido todavía. No hay evidencia de que funcione instalado:
no se ejecutó `docker compose up`, no se recibió correo, no se midió la tasa de
falsos positivos.

Lo que **sí** se verificó, contra fuente oficial y con la cita en
`VERSION.md` y `docs/10-LICENCIAS-Y-FUENTES.md`:

- Versión exacta de Rspamd (4.2.2) y su etiqueta oficial.
- Licencia exacta (Apache 2.0, **no** BSD).
- Topología real de workers de la versión 4.2.2, leyendo su archivo de
  configuración y el árbol del código fuente.
- Puertos que expone la imagen oficial.
- Healthcheck oficial de la imagen.
- Módulos `antivirus`, `dkim_signing`, `whitelist`, `greylist` y sus opciones,
  leyendo su código fuente en la etiqueta 4.2.2.
- Digests de imagen disponibles en Docker Hub.

Lo que **no** se verificó, porque no hay servidor donde probarlo:

- Que el `compose.yaml` arranque sin errores en un servidor real.
- La tasa real de falsos positivos de un cliente.
- La compatibilidad con la versión exacta de Postfix o Dovecot del cliente.
- La sintaxis exacta de `rspamadm dkim_keygen`.

El detalle completo está en **`docs/07-PRUEBAS-DE-ACEPTACION.md`**, separado en
"realmente ejecutado" y "pendiente".

---

## Requisitos del servidor

| Recurso | Mínimo | Recomendado | Nota |
|---|---|---|---|
| RAM | 2 GB | 4 GB | **Con antivirus: 4 GB mínimo, 8 GB recomendado** |
| CPU | 2 núcleos | 2 núcleos | Rspamd usa bien varios núcleos |
| Disco | 10 GB | 20 GB | Las firmas de ClamAV ocupan bastante |

### La RAM de ClamAV, en detalle

`clamd` carga el conjunto completo de firmas de virus **en memoria** al
arrancar. Una instancia normal consume **entre 1 GB y 2 GB** solo en firmas,
más lo que use para escanear.

Por eso ClamAV va **detrás del perfil `antivirus`** y no arranca por defecto:

```bash
# Sin antivirus (lo por defecto en este kit)
docker compose up -d

# Con antivirus
docker compose --profile antivirus up -d
```

Si el servidor no tiene esa memoria libre, **no active el antivirus**. Es
opcional: Rspamd filtra muy bien sin él. Un antivirus que hace caer el servidor
por falta de memoria es peor que no tener antivirus.

Si activa el antivirus y ClamAV no está disponible, Rspamd rechaza el correo
entrante. Es el comportamiento correcto desde seguridad, pero **hay que
saberlo**: por eso está documentado en
`docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## Contenido del paquete

```
hefesto-antispam-rspamd/
├── README.md                 Este documento
├── VERSION.md                Versiones, digests y topología verificados
├── LICENCIAS.md              Licencias y atribuciones
├── compose.yaml              Despliegue con Docker Compose
├── .env.example              Variables de entorno, sin secretos
├── .gitignore
├── config/local.d/           Configuración del cliente (edítela)
│   ├── redis.conf              Conexión a Redis
│   ├── worker-controller.inc   Contraseña de la interfaz web
│   ├── dkim_signing.conf       Firma del correo saliente
│   ├── whitelist.conf          Lista blanca contra falsos positivos
│   ├── greylist.conf           Ajustes de greylisting
│   └── antivirus.conf          Integración con ClamAV
├── scripts/
│   ├── backup-rspamd.sh        Respaldo verificado con SHA-256
│   └── restore-rspamd.sh       Restauración con validaciones
├── ejemplos/                 PLANTILLAS DE DEMOSTRACIÓN
│   ├── postfix-main.cf.demostracion
│   ├── dovecot-conf.d.demostracion
│   └── dkim-y-dns.demostracion.md
└── docs/                     Los 10 documentos de entrega
```

---

## Qué incluye y qué no

### Incluye

- Filtro antispam completo con Rspamd 4.2.2: listas negras, heurísticas,
  bayes, greylisting y rate limiting.
- Firma **DKIM** del correo saliente, con los registros DNS que exige.
- Integración con **Postfix** mediante milter.
- Integración con **Dovecot** (aplicación del filtro al correo ya almacenado).
- **ClamAV** opcional.
- Respaldo y restauración con manifiesto y verificación SHA-256.
- Interfaz web de estadísticas y entrenamiento.

### NO incluye

- **El servidor de correo.** Ni Postfix ni Dovecot ni el servidor IMAP/POP.
  Eso es otro servicio. Ver la advertencia de arriba.
- **Los registros DNS.** El kit indica qué publicar; publicarlos es tarea de
  quien controla la zona DNS del cliente.
- **El correo del cliente**, ni las bandejas, ni los usuarios.
- **Certificados TLS** del proxy, si se expone algo por HTTPS.
- **Aislamiento entre clientes.** Ver más abajo.

### Sobre multi-cliente

Cada instalación es **de un solo cliente**. No hay aislamiento ni
multi-tenancy: si se corre el mismo kit para dos clientes, hay que desplegar
una instancia separada por cliente, con sus propios volúmenes. **Este kit no
soporta dos clientes en una misma instalación y no se debe intentar.**

---

## Inicio rápido

Requisitos previos: un servidor Ubuntu o Debian con Docker y el plugin Docker
Compose instalados, y el directorio del kit copiado en el servidor.

```bash
# 1. Crear el archivo de variables a partir de la plantilla
cp .env.example .env

# 2. Editar .env: revisar zona horaria, puertos y resolutor DNS
nano .env

# 3. Levantar
docker compose up -d

# 4. Ver el estado (los healthchecks deben decir "healthy")
docker compose ps

# 5. Verificar que Rspamd responde
docker compose exec rspamd rspamadm configtest

# 6. Ponerle contraseña a la interfaz web
docker compose exec rspamd rspamadm pw
#    Copie el resultado a config/local.d/worker-controller.inc y desactive
#    la línea. Después: docker compose restart rspamd
```

Procedimiento completo, con verificación en cada paso:
**`docs/01-INSTALACION-DOCKER.md`**.

### Una nota sobre los puertos

Este kit **no pública ningún puerto SMTP**.

Rspamd no escucha en SMTP: es un *milter*, o sea un servicio al que el servidor
de correo le entrega cada mensaje ya recibido. Los únicos puertos que pública el
kit son los de Rspamd, y **todos están atados a `127.0.0.1`**:

| Puerto del host | Para qué | ¿Acceso externo? |
|---|---|---|
| 11332 | Milter (donde entra Postfix) | No |
| 11334 | Interfaz web de administración | No, solo por túnel SSH |
| 11333 | API HTTP de diagnóstico | No |

Para acceder a la interfaz web:

```bash
ssh -L 11334:127.0.0.1:11334 usuario@servidor-del-cliente
# Después abra http://localhost:11334 en el navegador
```

Ni Redis (6379) ni ClamAV (3310) se publican jamás.

---

## Rspamd no es perfecto

### Qué pasa cuando el filtro se equivoca

Cuando Rspamd descarta un correo legítimo, el remitente no se entera de nada:
su mensaje simplemente no llega. Desde el punto de vista del cliente es una
pérdida invisible.

Las dos causas más comunes de falso positivo:

1. **Greylisting.** El primer correo de un remitente nuevo se retiene para ver
   si el servidor de origen reintenta. El cliente lo ve como "el correo se
   atrasó 10 minutos" o directamente "no llegó". Ver
   `config/local.d/greylist.conf`.
2. **Lista blanca incompleta.** Un proveedor de confianza que todavía no está en
   la lista y cuyo correo no supera el puntaje.

### El flujo para agregar algo a la lista blanca

1. El cliente avisa que no llegó un correo de un remitente conocido.
2. Se busca ese remitente en la interfaz web, pestaña de historial.
3. Se agrega su dominio a `config/local.d/whitelist.conf`:

   ```
   whitelist {
     rules {
       WHITELIST_CLIENTE_N {
         priority = 1;
         domains = ["dominio-real.cl"];
         score = 2.0;
       }
     }
   }
   ```

4. Se recarga Rspamd: `docker compose restart rspamd`.
5. Se espera al **cliente que avisó** y se le confirma.

Agregar a la lista blanca es barato y reversible. Ante la duda, **agregue antes
que diga**.

### Cómo se mide el problema

No se puede prometer un número de falsos positivos sin medirlo. El kit incluye:

- La **interfaz web** con historial y estadísticas (puerto 11334, por túnel SSH).
- El **API HTTP** de diagnóstico (puerto 11333) para consultar por mensaje.
- Entrenamiento de bayes desde la interfaz.

El procedimiento concreto, con los comandos para contar y medir, está en
`docs/07-PRUEBAS-DE-ACEPTACION.md`, sección "Medición de falsos positivos".

### El plan de las primeras dos semanas

Es el periodo donde más se llama, y conviene decirlo de antemano:

| Días | Qué hacer |
|---|---|
| 1 a 3 | Activar greylisting **desactivado** (`RSPAMD_USE_GREYLIST=0`). Cargar la lista blanca con los clientes y proveedores conocidos. |
| 4 a 7 | Activar greylisting. Avisar al cliente del comportamiento del primer correo. Revisar el historial a diario. |
| 8 a 14 | Entrenar bayes con lo que el cliente marque. Agregar a la lista blanca lo que se perdió. |

Cerrar la regla: **si no está en la lista blanca, se agrega a la lista blanca**.
La lista blanca es la red de seguridad; todo lo demás es segundo filtro.

---

## Seguridad del paquete

- Cero secretos reales en el kit. `.env.example` solo tiene valores falsos.
- La contraseña de la interfaz web **no va en `.env`**: es un hash que se pega
  en `config/local.d/worker-controller.inc`, y ese archivo está en
  `.gitignore`.
- Los scripts de respaldo requieren privilegios de root y **verifican** lo que
  hacen.
- La restauración **rechaza** rutas que escapan del archivo comprimido
  (path traversal) y **se niega** a sobrescribir un destino ocupado sin
  `--force` explícito.
- La restauración deja el servicio **detenido** a propósito, hasta que alguien
  revise.
- **El respaldo contiene las claves privadas DKIM y el hash de la contraseña.**
  Quien tenga el archivo puede firmar correo como el cliente. Guárdelo con la
  misma custodia que el correo del cliente.

---

## Qué falta probar

Detalle en `docs/07-PRUEBAS-DE-ACEPTACION.md`. Resumen:

- [ ] Que `compose.yaml` levante los tres servicios en un servidor real.
- [ ] Que los healthchecks pasen.
- [ ] Medir la tasa real de falsos positivos con correo del cliente.
- [ ] Confirmar la sintaxis exacta de `rspamadm dkim_keygen` en 4.2.2.
- [ ] Probar la firma DKIM de punta a punta contra un verificador externo.
- [ ] Probar respaldo y restauración en un servidor de verdad.
- [ ] Validar la configuración de Postfix y Dovecot contra las versiones que
      usa el cliente.

Nada de lo anterior se ha ejecutado. **No se lo presente al cliente como
funcionando.**

---

## Documentación

| Documento | Qué resuelve |
|---|---|
| `docs/01-INSTALACION-DOCKER.md` | Instalación paso a paso desde Ubuntu/Debian limpio |
| `docs/02-INSTALACION-COOLIFY.md` | Despliegue en Coolify y por qué aquí no aplica del todo |
| `docs/03-VARIABLES-Y-COMO-OBTENERLAS.md` | Cada variable, de dónde sale, qué pasa si se cambia |
| `docs/04-PRIMERA-CUENTA-Y-USUARIOS.md` | Primer acceso, contraseña, acceso por túnel SSH |
| `docs/05-RESPALDOS-Y-RESTAURACION.md` | Qué se respalda, qué no, cómo se restaura |
| `docs/06-ACTUALIZACIONES-Y-REVERSION.md` | Actualizar con versión fijada y volver atrás |
| `docs/07-PRUEBAS-DE-ACEPTACION.md` | Qué se verificó y qué falta, separado |
| `docs/08-SERVICIOS-COMERCIALES.md` | Qué se puede vender y qué no se puede prometer |
| `docs/09-EXPORTACION-O-TRASPASO.md` | Cómo exportar los datos del kit |
| `docs/10-LICENCIAS-Y-FUENTES.md` | Licencias y enlaces de origen de todo |

---

## Licencia

Rspamd es **Apache License 2.0**. Redis es BSD de 3 cláusulas. ClamAV es GPL-2.0.
Ver `LICENCIAS.md` y `docs/10-LICENCIAS-Y-FUENTES.md`.

Hefesto Studio vende la puesta en marcha, el mantenimiento y el soporte, **no el
software**.