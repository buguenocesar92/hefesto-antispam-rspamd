# 05 — Respaldos y restauración

> **Estado: no ejecutado.** Los scripts están escritos y su sintaxis fue
> verificada, pero **no se corrieron de punta a punta en un servidor**. La lista
> de pendientes está al final y en `docs/07-PRUEBAS-DE-ACEPTACION.md`.

Scripts del kit:

- `scripts/backup-rspamd.sh` — genera el respaldo.
- `scripts/restore-rspamd.sh` — lo restaura.

Ambos son **destructivos en el sentido de que modifican el estado del
servidor**, así que léalos antes de correrlos.

---

## 1. Qué es persistente

El kit tiene **tres volúmenes nombrados**. No todo se respalda.

| Volumen | Ruta en el contenedor | Qué contiene | ¿Se respalda? |
|---|---|---|---|
| `rspamd-data` | `/var/lib/rspamd` | Claves privadas DKIM, archivos del clasificador bayes, mapas aprendidos, cache de hyperscan | **Sí** |
| `redis-data` | `/data` | Clasificadores bayes, greylist, historial, límites de tasa, claves DKIM guardadas en Redis | **Sí** |
| `clamav-data` | `/var/lib/clamav` | Firmas de virus | **No** |

Además, `config/local.d/` en el host, que es un directorio normal montado de
solo lectura dentro del contenedor. **Se respalda.**

---

## 2. Qué NO se respalda, y por qué

### Firmas de ClamAV — porque se redescargan solas

`clamd` descarga sus firmas al arrancar. `FRESHCLAMD_CHECKS` en el kit está en
`1`: una descarga por arranque.

Copiar el volumen de firmas son **gigabytes** que se descartan en la primera
reinstalación del contenedor. El tiempo de respaldo dejaría de ser aceptable
para nada útil.

**Consecuencia:** después de restaurar, ClamAV puede tardar **varios minutos**
en cargar firmas nuevas la primera vez. No es un error.

### Imágenes de Docker — se vuelven a descargar

No son datos del cliente. Se descargan de nuevo del registro.

### El `.env` — sin secretos y versionado

No contiene secretos y ya está en el repositorio del cliente. Si el kit está
versionado en git, no hay nada que respaldar.

---

## 3. Cómo obtener una copia coherente

**Una copia hecha con Rspamd corriendo no sirve.**

El volumen `rspamd-data` se modifica mientras el servicio está vivo. Copiarlo a
media escritura produce un archivo de bayes **corrupto**, que en el mejor caso
se descarta y en el peor hace que Rspamd no arranque.

Por eso `backup-rspamd.sh`:

1. **Detiene Rspamd** antes de copiar. Es el único escritor de
   `/var/lib/rspamd`.
2. **Fuerza el guardado de Redis** con `redis-cli SAVE`, que es **síncrono**:
   Redis deja de responder hasta que el dump está escrito. Es lo que garantiza
   consistencia, a cambio de unos segundos de pausa en el filtrado.
3. Copia con `docker cp`, que funciona con contenedores detenidos.

### El impacto en el servicio

Durante el respaldo, Rspamd está **detenido**. Según `milter_default_action` de
Postfix:

- Con `tempfail` (lo que recomienda este kit): el correo **se acumula en la
  cola** y se entrega cuando Rspamd vuelve. Nada se pierde.
- Con `accept`: el correo pasa **sin filtrar** durante la pausa. Evitar.

El respaldo tarda **segundos a un par de minutos**, dependiendo del volumen.

---

## 4. Manifiesto y sumas de verificación

Cada respaldo produce una carpeta y un archivo comprimido:

```
respaldos/
├── rspamd-20261017-143022/
│   ├── MANIFIESTO.txt        Qué contiene, qué no, y de qué versiones
│   ├── CHECKSUMS.sha256      SHA-256 de cada archivo
│   ├── ARCHIVO.txt           Marca de "terminado bien"
│   ├── datos/                Contenido de /var/lib/rspamd
│   ├── redis/
│   │   └── dump.rdb
│   └── config/
│       └── local.d/
└── rspamd-20261017-143022.tar.gz
└── rspamd-20261017-143022.tar.gz.sha256
```

Dos niveles de verificación:

| Nivel | Qué cubre | Cómo se comprueba |
|---|---|---|
| `.tar.gz.sha256` | Que el archivo comprimido no se alteró al copiarlo o transmitirse | `sha256sum -c` |
| `CHECKSUMS.sha256` | Que **ningún archivo dentro** cambió | `sha256sum -c` dentro de la carpeta |

`MANIFIESTO.txt` registra las **imágenes exactas** del servidor de origen, para
que dentro de un año se sepa con qué versiones se generó el respaldo.

---

## 5. El respaldo se marca completo solo al terminar bien

Este es el punto más importante del diseño.

`ARCHIVO.txt` se escribe **al final, después de comprimir**. Es lo que
`restore-rspamd.sh` exige para restaurar.

Si algo falla a mitad de camino —falta de disco, se corta el cable, se llena el
volumen— la trampa de limpieza del script **borra la carpeta incompleta**.

Resultado: **no queda un respaldo a medias que alguien pueda restaurar por
error creyendo que sirve.** Si no hay `ARCHIVO.txt`, no hay respaldo.

El script también devuelve el servicio al estado en que lo encontró: si Rspamd
estaba corriendo, vuelve a correr, incluso si el respaldo falló.

---

## 6. Restauración: comprobaciones antes de extraer

`restore-rspamd.sh` no extrae nada sin verificar antes:

1. **Suma SHA-256** del `.tar.gz`, si existe el archivo acompañante.
2. **Lista el contenido** del comprimido sin extraer y busca rutas sospechosas:
   - entradas que empiezan con `/` (absolutas);
   - entradas con `..` (recorrido de directorios, aka path traversal).

   Si encuentra alguna, **aborta**. Esta es la defensa contra un archivo
   manipulado que intenta escribir fuera del directorio de destino.

3. Extrae **solo a un directorio temporal**, nunca sobre el destino final.

4. **Marca de completitud:** sin `ARCHIVO.txt`, aborta.

5. **SHA-256 de cada archivo interno** contra `CHECKSUMS.sha256`. Si uno no
   calza, aborta sin haber tocado nada.

6. Recién después de todo eso escribe en los volúmenes.

---

## 7. Rechazo sobre destinos ocupados

Si el volumen de destino ya tiene datos, el script **se niega a seguir**:

```
Se rehúsa sobrescribir. Use --force si de verdad quiere.
```

Con `--force`, **no borra**: mueve el contenido existente a un directorio de
resguardo y escribe encima. Lo mismo con `config/local.d`: la configuración
anterior se aparta a `config/local.d.respaldo-<fecha>`.

Esto aplica también al caso de restaurar sobre una instalación **viva**: el
script nunca asume que el destino está limpio.

### Cómo verificar el resultado

```bash
docker compose exec redis redis-cli --scan | head
docker compose exec rspamd rspamadm configtest
```

---

## 8. Nunca DROP ni sobrescritura automática

No hay ningún `DROP`, ni `rm -rf` sobre volúmenes, ni sobrescritura
"silenciosa" en ninguna rama del script.

Todo lo que se reemplaza **se aparta primero**. Es más ocupa disco, pero deja
siempre una forma de volver atrás sin haber restaurado nada.

---

## 9. Secretos que hay que conservar aparte

El respaldo **contiene** estos secretos:

| Secreto | Dónde está | Qué pasa si se pierde |
|---|---|---|
| Claves privadas DKIM | `datos/` (`/var/lib/rspamd/dkim/`) | Hay que generar claves nuevas **y publicar los TXT nuevos en DNS**. Todo el correo saliente queda sin firma válida hasta que se publique. |
| Hash de la contraseña de la interfaz web | `config/local.d/worker-controller.inc` | Hay que generar una contraseña nueva. Molestia, no pérdida crítica. |

**El `.tar.gz` es tan sensible como el correo del cliente.** Quien tenga el
archivo puede **firmar correo como `ejemplo.cl`**. Eso habilita fraude
phishing creíble que pasa la validación DKIM.

Recomendación:

- Guardar los respaldos cifrados o en un destino con la misma custodia que el
  correo del cliente.
- **Borrar los respaldos viejos.** Cada copia es una llave de firma guardada
  fuera de lugar.
- No mandarlos por correo. Usar un canal cifrado.

**Lo que NO va en el respaldo:** el correo de los usuarios, las cuentas, las
contraseñas del servidor de correo. Eso lo respalda el cliente por su cuenta,
en su propio sistema.

---

## 10. El servicio queda detenido

Al terminar, `restore-rspamd.sh` **deja Rspamd y Redis detenidos**, y lo dice
en pantalla.

Es intencional: restaurar en caliente es la forma más rápida de corromper un
volumen. Alguien tiene que revisar que todo está bien antes de volver a
operar.

```bash
# Para volver a operarlo, después de revisar
docker compose start rspamd redis

# Y si usa antivirus
docker compose --profile antivirus start clamav
```

Si el script falla a mitad de camino, la trampa también deja el servicio
detenido y muestra el mensaje. No queda funcionando a medias.

---

## 11. Límites y qué hacer ante un fallo parcial

### Límites conocidos de este diseño

| Límite | Detalle |
|---|---|
| Volcado de Redis **en línea** | `redis-cli SAVE` congela Redis mientras escribe. Con mucha carga, la cola de correo se detiene. Se tolera a cambio de consistencia. |
| Sin respaldo de las **firmas** de ClamAV | Después de restaurar, el antivirus tarda minutos en volver a estar operativo. |
| No incluye **correo de usuarios** | Este kit no guarda los correos. |
| No incluye **DKIM en DNS** | El respaldo guarda la clave privada, **no** el registro TXT. Si se pierde, hay que publicar el registro de nuevo. |
| **Un solo cliente** por instalación | No hay aislamiento. |
| Restauración **probada solo en diseño** | No se ejecutó de punta a punta. |

### Ante un fallo parcial

1. **El respaldo quedó incompleto** → no hay `ARCHIVO.txt`. El script lo borró
   solo. No use lo que haya quedado.

2. **Falló la copia, Rspamd quedó detenido** → el servicio vuelve solo al estado
   original. Si no, `docker compose start rspamd`.

3. **Falló la restauración** → revise `/var/log` del servidor y el mensaje del
   script. Lo que el script **no** tocó sigue intacto.

4. **Restauró pero el dominio cambió** → las claves DKIM del respaldo no
   corresponden al DNS actual. **Desactive la firma DKIM** hasta regenerar las
   claves y publicar los registros.

5. **Restauró un respaldo antiguo y hay muchos falsos positivos** → es
   esperable: el aprendizaje bayesiano era el de esa fecha. Recargue la lista
   blanca con la información actual.

---

## Procedimiento

### Respaldo

```bash
cd /opt/hefesto/hefesto-antispam-rspamd
sudo ./scripts/backup-rspamd.sh

# Verificar el resultado
sha256sum -c respaldos/rspamd-*.tar.gz.sha256
ls -lh respaldos/
```

### Restauración

```bash
cd /opt/hefesto/hefesto-antispam-rspamd

# Ver la ayuda
sudo ./scripts/restore-rspamd.sh --help

# Restaurar (rechaza si el destino está ocupado)
sudo ./scripts/restore-rspamd.sh --archivo respaldos/rspamd-20261017-143022.tar.gz

# Forzar, conservando la configuración actual
sudo ./scripts/restore-rspamd.sh --archivo respaldos/... --force --sin-config
```

**Recomendación operativa:** un respaldo diario, keepers tres semanas como
mínimo, y **uno antes de cada cambio de configuración**.