# DEMOSTRACIÓN — Receta de DKIM y registros DNS

> **PLANTILLA DE DEMOSTRACIÓN.** Los dominios, los selectores y las claves de
> este documento son inventados. No copie los valores. Genere las claves en el
> servidor del cliente y publique el registro TXT que salga de ahí.
>
> Este ejemplo **no se ha ejecutado en ningún servidor**. La receta está
> construida con las opciones que sí se verificaron leyendo el código de
> Rspamd 4.2.2, pero los comandos de generación de claves están marcados como
> **pendientes de verificar** en `docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## Qué es DKIM y qué resuelve

DKIM (DomainKeys Identified Mail) es la forma en que un servidor de correo
**firma digitalmente** el correo que envía, diciendo "esto salió realmente de
`ejemplo.cl` y nadie lo modificó en el camino".

Sin DKIM, el correo saliente de una Pyme que usa Google Workspace, su hosting
web o un servicio de envío automático suele:

- llegar a la carpeta de spam del destinatario;
- ser asociado a "correo no autenticado" y perder reputación;
- ser difícil de distinguir de un fraude que dice venir de la empresa.

Con DKIM firmado correctamente, el correo sale de la Pyme con sello verificable.
Gmail, Outlook y otros lo tratan mejor, y el cliente deja de ver sus propios
correos en la carpeta de spam de los demás.

---

## Las tres piezas

DKIM necesita **tres cosas que van juntas**. Si falta una, no funciona:

1. **Una clave privada** en el servidor. Rspamd firma con ella.
   → Vive en el volumen `rspamd-data`, en `/var/lib/rspamd/dkim/`.

2. **Una clave pública** publicada en DNS, como registro **TXT**.
   → La pública quien administra la zona del cliente.

3. **Una regla DNS SPF** que autorice al servidor a enviar por el dominio.
   → Si falta, el correo falla la alineación DMARC en los receptores estrictos.

Las tres se configuran en archivos distintos y en personas distintas. Ese es el
punto de la receta.

---

## Paso 1 — Publicar un SPF que autorice al servidor

**Archivo de zona DNS, tipo `TXT`, nombre `@`:**

```
v=spf1 ip4:203.0.113.10 -all
```

- `v=spf1`: marca que es un registro SPF.
- `ip4:203.0.113.10`: la IP del servidor de correo del cliente.
- `-all`: rechaza todo lo que venga de otro lado. Es lo estricto y lo correcto
  si el cliente **no** usa otro servicio para enviar correo con su dominio.

**Si el cliente usa otro servicio para enviar** (por ejemplo Mailchimp o
Google Workspace), no puede dejar un solo `v=spf1`: necesita incluirlo:

```
v=spf1 ip4:203.0.113.10 include:_spf.google.com -all
```

> **Punto de atención comercial.** Muchos clientes no saben que sus
> boletines y sus campañas los manda un servicio distinto del que usa para el
> correo diario, con lo que el
> SPF queda mal. Revise antes de poner `-all`, porque un SPF demasiado estricto
> hace que el cliente deje de poder enviar su propio boletín.

El SPF **no es parte de este kit**: es configuración de zona DNS que hay que
hacer en el panel del cliente o en su proveedor de hosting.

---

## Paso 2 — Generar el par de claves en el servidor

Esto se hace **en el servidor del cliente**, nunca en una máquina del estudio:
la clave privada no debe viajar por correo ni por chat.

```bash
# Con el kit levantado:
docker compose exec rspamd rspamadm dkim_keygen \
    -s dkim \
    -d ejemplo.cl
```

**Estado de esta instrucción: PENDIENTE DE VERIFICAR.** El nombre del comando
`dkim_keygen` y sus opciones `-s` / `-d` provienen de la práctica habitual con
Rspamd, pero **no se pudieron confirmar contra el código de la versión 4.2.2**
durante la preparación de este kit: el ejecutable `rspamadm` registra sus
comandos por otra vía y no se pudo listar el conjunto completo.

**Antes de confiar en el comando, verifíquelo usted mismo:**

```bash
docker compose exec rspamd rspamadm --help
docker compose exec rspamd rspamadm dkim_keygen --help
```

Si la salida difiere de lo que dice esta receta, **mande la salida correcta a
Hefesto** para corregir el documento. No adivine los valores.

Dónde quedan las claves, según la configuración del kit
(`config/local.d/dkim_signing.conf`):

```
/var/lib/rspamd/dkim/ejemplo.cl.dkim.key    <- privada, NO se publica
/var/lib/rspamd/dkim/ejemplo.cl.dkim.pub    <- pública, SÍ se publica
```

La ruta sale de la opción `path` del módulo `dkim_signing`, cuyo valor por
defecto en 4.2.2 es `$DBDIR/dkim/$domain.$selector.key`. `$DBDIR` corresponde a
`/var/lib/rspamd`, que es el volumen persistente del kit.

---

## Paso 3 — Publicar la clave pública en DNS

Tome el **contenido** del archivo `.pub` que generó el paso anterior.

**Archivo de zona DNS, tipo `TXT`, nombre `dkim._domainkey`:**

```
v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBg...==
```

Desglose:

| Parte | Qué es |
|---|---|
| `v=DKIM1` | Versión de DKIM. Siempre esa. |
| `h=sha256` | Algoritmo de hash. Use `sha256`; `sha1` está obsoleto. |
| `k=rsa` | Tipo de clave. RSA es el más compatible. |
| `p=...` | La clave pública en base64. Va sin los angle brackets `< >`. |

> **Este texto de ejemplo está incompleto a propósito.** La parte `p=` real
> tiene varios cientos de caracteres. Copie la del servidor, no la de acá.

### El nombre del registro

Con selector `dkim`, el nombre completo es:

```
dkim._domainkey.ejemplo.cl
```

Si usa otro selector, cambia la parte de después de `domainkey`.

### Confirmar que se publicó

Desde cualquier máquina:

```bash
dig TXT dkim._domainkey.ejemplo.cl +short
```

Tiene que devolver una línea que empiece con `v=DKIM1`. Si no devuelve nada,
el problema es de zona DNS, no de Rspamd: **no siga avanzando hasta que esto
responda**.

Si su proveedor de DNS parte el registro en varios trozos ("string split"),
Rspamd igual lo lee bien; el reparto automático de los paneles modernos
(Cloudflare, Route 53) no son problema.

---

## Paso 4 — Activar la firma en Rspamd

Edite `config/local.d/dkim_signing.conf`:

```
dkim_signing {
  domain = ["ejemplo.cl"];
  selector = "dkim";
  path = "$DBDIR/dkim/$domain.$selector.key";

  sign_authenticated = true;
  sign_local = true;

  check_pubkey = true;

  allow_username_mismatch = false;
  allow_hdrfrom_mismatch = false;

  use_redis = false;
}
```

Reinicie:

```bash
docker compose restart rspamd
```

### Qué hace `check_pubkey = true`

Es el ajuste de seguridad más importante de este archivo, y no viene activo por
defecto.

Con `check_pubkey = true`, Rspamd **consulta el registro TXT
`dkim._domainkey.<dominio>` antes de firmar**. Si no existe o está roto,
**no firma** y deja el hecho registrado en el log.

Qué previene: el escenario en que el servidor firma con una clave que nadie
conoce, el correo sale sin que nadie lo pueda validar, y la reputación de
`ejemplo.cl` se daña. Es mejor no firmar que firmar con una clave pública.

Qué cuesta: si el DNS todavía no está propagado, **Rspamd deja de firmar** hasta
que lo esté. Hay que publicarlo antes de activar.

### Qué NO activar (y por qué)

| Ajuste | Valor | Razón |
|---|---|---|
| `allow_username_mismatch` | `false` | En `true`, cualquiera que se autentique en el servidor podría enviar correo como `presidente@ejemplo.cl`. Es suplantación. |
| `allow_hdrfrom_mismatch` | `false` | Mismo problema, por el remitente declarado en `From:`. |
| `allow_hdrfrom_multiple` | `false` | Permite varios remitentes en un mismo correo. |

Estos quedan en `false` a propósito. Si el cliente pide habilitarlos, hay que
entender antes qué está abriendo.

---

## Paso 5 — Verificar que la firma funciona

### Desde el servidor

```bash
# 1. Revisar que Rspamd registró la firma
docker compose logs -f rspamd

# 2. Enviar un correo de prueba a un buzón externo
echo "Prueba DKIM" | mail -s "prueba dkim" destinatario@otro-servicio.cl
```

### Desde el destinatario

Revise las cabeceras del correo recibido. Tiene que aparecer algo como:

```
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=ejemplo.cl; s=dkim;
    h=from:to:subject:date; bh=...; b=...
```

La línea clave es `d=ejemplo.cl; s=dkim`.

### Con una herramienta externa

Herramientas públicas como los verificadores de DKIM que ofrecen los
proveedores de correo, o servicios de diagnóstico de correo, permiten pegar el
mensaje y ver si la firma valida. **El resultado debe decir `pass`.**

Si dice `fail`, mire en este orden:

1. ¿El registro TXT está publicado? → `dig TXT dkim._domainkey.ejemplo.cl`
2. ¿La clave pública es la del servidor que está firmando?
3. ¿El `domain` en `dkim_signing.conf` calza con el dominio de la zona?

---

## Mantenimiento de DKIM

### Rotar la clave

Se recomienda **cada 6 a 12 meses**, o de inmediato si se sospecha que la clave
se filtró.

El problema clásico de la rotación: hay que publicar la clave nueva en DNS
**antes** de firmar con ella, o el correo deja de validar durante la
propagación. Rspamd tiene el selector en el nombre de la clave justamente para
poder tener dos en paralelo.

Procedimiento breve:

1. Generar clave con un selector nuevo: `dkim2`.
2. Publicar `dkim2._domainkey` con la clave nueva, **dejando la vieja
   `dkim._domainkey` publicada**.
3. Configurar Rspamd con los dos selectores.
4. Confirmar que firma con `s=dkim2` y que valida.
5. Recién entonces, **eliminar** `dkim._domainkey` de DNS.

### Respaldar la clave privada

**Va en el respaldo del kit, no aparte.** Vive en el volumen `rspamd-data` y
`scripts/backup-rspamd.sh` la incluye.

Ver `docs/05-RESPALDOS-Y-RESTAURACION.md`, sección "Qué secretos hay que
conservar aparte".

---

## DKIM no es autenticación completa

DKIM dice "esto salió de `ejemplo.cl`". **No dice quién lo envió.**

Para eso están los otros dos controles, que son parte del servidor de correo del
cliente, no de este kit:

- **SPF:** qué servidores tienen permiso para enviar por el dominio.
- **DMARC:** qué hacer con el correo que falla ambos controles, y a quién
  avisar.

Con los tres juntos se forma **From Domain Alignment**, y es lo que realmente
frena el fraude de suplantación de dominio.

DKIM es **una de tres piezas**, y por sí solo es un avance real pero no una
solución completa.

---

## Resumen de registros DNS que exige este kit

| Nombre | Tipo | Para qué | ¿Dónde se pública? |
|---|---|---|---|
| `@` | `TXT` (SPF) | Autorizar al servidor a enviar | Zona del cliente |
| `dkim._domainkey` | `TXT` | Clave pública de DKIM | Zona del cliente |
| `_dmarc` | `TXT` | Política DMARC | Zona del cliente |
| `*.dkim._domainkey` | `TXT` | Wildcard DKIM (opcional) | Zona del cliente |
| `postmaster` / `abuse` | — | Buzones obligatorios | Zona del cliente |

El contenido exacto del SPF, DKIM y DMARC depende de cada cliente y **se
confirma en la reunión de inicio**, mirando qué servicios usa hoy para enviar.
No se aplica nada de esto sin revisarlo.