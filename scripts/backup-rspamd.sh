#!/usr/bin/env bash
# =============================================================================
# Hefesto Studio — Kit Rspamd
# Respaldo del estado que NO se regenera.
# =============================================================================
#
# QUE RESPALDA ESTE SCRIPT
#   1. Volumen `rspamd-data` (/var/lib/rspamd dentro del contenedor).
#      Aqui viven las claves privadas DKIM, los archivos del clasificador
#      bayes, los mapas aprendidos y la cache de hyperscan.
#   2. Volumen `redis-data` (/data).
#      Aqui viven los clasificadores bayes, el greylist, el historial, los
#      limites de tasa y las claves DKIM que Rspamd guarda en Redis.
#   3. `config/local.d`, que es la configuracion del cliente.
#
# QUE NO RESPALDA Y POR QUE
#   - Firmas de ClamAV. El contenedor clamav las redescarga por su cuenta al
#     arrancar. Copiarlas cuesta gigabytes y no aporta nada.
#   - La imagen del contenedor. Se descarga de nuevo desde el registro.
#   - El `.env`. No contiene secretos, pero es texto chico: el cliente lo
#     versiona por su cuenta en el repositorio.
#
# -----------------------------------------------------------------------------
# EL RESPALDO CONTIENE SECRETOS
# -----------------------------------------------------------------------------
# El archivo resultante incluye las claves privadas DKIM y el hash de la
# contrasena de la interfaz web. Quien tenga una copia del `.tar.gz` puede
# firmar correo como el cliente. Guardelo con la misma custodia que la copia
# de seguridad del correo del cliente, y borre las copias viejas.
# -----------------------------------------------------------------------------
#
# USO
#   ./scripts/backup-rspamd.sh                  # respalda al directorio actual
#   ./scripts/backup-rspamd.sh --force          # no pide confirmacion
#   ./scripts/backup-rspamd.sh --dir /mnt/nas   # elige donde escribir
#   ./scripts/backup-rspamd.sh --help
#
# SALIDA: deja el servicio como lo encontro, es decir, corriendo.
# =============================================================================

set -euo pipefail

# --- Identificacion -----------------------------------------------------------
KIT_ID="hefesto-antispam-rspamd"
SERVICIO_RSPAMD="rspamd"
SERVICIO_REDIS="redis"
VOLUMEN_RSPAMD="/var/lib/rspamd"
VOLUMEN_REDIS="/data"

# --- Codigos de salida --------------------------------------------------------
E_OK=0
E_USO=2
E_PRECONDICION=3
E_SIN_CONTENEDOR=4
E_FALLO_RESPALDO=5

# --- Variables por linea de comando ------------------------------------------
RUTA_BASE=""
FORZAR=0

# --- Presentacion -------------------------------------------------------------
info()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
aviso() { printf '[%s] AVISO: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
error() { printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

uso() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit "$E_USO"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir)    [ "$#" -ge 2 ] || { error "--dir necesita una ruta"; exit "$E_USO"; }
                  RUTA_BASE="$2"; shift 2 ;;
        --force)  FORZAR=1; shift ;;
        --help|-h) uso ;;
        *) error "Argumento desconocido: $1"; uso ;;
    esac
done

# --- Precondiciones -----------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { error "Este script necesita privilegios de root."; exit "$E_PRECONDICION"; }
command -v docker >/dev/null 2>&1 || { error "No se encontro 'docker'."; exit "$E_PRECONDICION"; }
docker compose version >/dev/null 2>&1 || { error "No se encontro el plugin 'docker compose'."; exit "$E_PRECONDICION"; }
docker info >/dev/null 2>&1 || { error "El demonio Docker no responde. Esta corriendo?"; exit "$E_PRECONDICION"; }

RAIZ_KIT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ_KIT"

[ -f "compose.yaml" ] || { error "No se encontro compose.yaml en $RAIZ_KIT"; exit "$E_PRECONDICION"; }

if [ -z "$RUTA_BASE" ]; then
    RUTA_BASE="$RAIZ_KIT/respaldos"
else
    case "$RUTA_BASE" in
        /*) : ;;
        *) RUTA_BASE="$(pwd)/$RUTA_BASE" ;;
    esac
fi

# Se normaliza la ruta para que los nombres del manifiesto no dependan de donde
# se ejecute el script.
mkdir -p "$RUTA_BASE"
RUTA_BASE="$(cd "$RUTA_BASE" && pwd)"

MARCA_TIEMPO="$(date '+%Y%m%d-%H%M%S')"
NOMBRE="rspamd-${MARCA_TIEMPO}"
DESTINO="$RUTA_BASE/$NOMBRE"

ARCHIVO_FINAL="$RUTA_BASE/$NOMBRE.tar.gz"
CHECKSUMS="$DESTINO/CHECKSUMS.sha256"
MANIFIESTO="$DESTINO/MANIFIESTO.txt"

# --- Confirmacion -------------------------------------------------------------
if [ "$FORZAR" -ne 1 ]; then
    if [ -e "$DESTINO" ] || [ -e "$ARCHIVO_FINAL" ]; then
        error "Ya existe un respaldo con el nombre $NOMBRE. Use --dir u otro minuto."
        exit "$E_PRECONDICION"
    fi
    info "Se creara $ARCHIVO_FINAL"
    info "El respaldo contiene claves DKIM privadas. Confirme que el destino es seguro."
    printf 'Escriba SI para continuar: '
    read -r RESPUESTA
    [ "$RESPUESTA" = "SI" ] || { info "Cancelado por el operador."; exit "$E_OK"; }
fi

# --- Localizacion de contenedores -------------------------------------------
id_contenedor() {
    # `ps -aq` incluye los detenidos: hace falta el ID despues de `stop`.
    docker compose ps -aq "$1" 2>/dev/null | head -n 1
}

CID_RSPAMD="$(id_contenedor "$SERVICIO_RSPAMD")"
CID_REDIS="$(id_contenedor "$SERVICIO_REDIS")"

[ -n "$CID_RSPAMD" ] || { error "No existe el contenedor de $SERVICIO_RSPAMD. Levante el kit antes de respaldar."; exit "$E_SIN_CONTENEDOR"; }
[ -n "$CID_REDIS" ]   || { error "No existe el contenedor de $SERVICIO_REDIS. Levante el kit antes de respaldar."; exit "$E_SIN_CONTENEDOR"; }

RSPAMD_ESTABA_ARRIBA=0
if [ "$(docker inspect -f '{{.State.Running}}' "$CID_RSPAMD" 2>/dev/null || echo false)" = "true" ]; then
    RSPAMD_ESTABA_ARRIBA=1
fi

# --- Trampa de limpieza -------------------------------------------------------
# Si algo falla a mitad de camino, Rspamd no debe quedar detenido en silencio.
limpiar() {
    if [ "$RSPAMD_ESTABA_ARRIBA" -eq 1 ]; then
        info "Devolviendo $SERVICIO_RSPAMD a su estado original (corriendo)."
        docker compose start "$SERVICIO_RSPAMD" >/dev/null 2>&1 || \
            aviso "No se pudo reiniciar $SERVICIO_RSPAMD. Revise con: docker compose ps"
    fi
    # Un respaldo a medias se marca como inutil para que nadie lo restaure.
    if [ -d "$DESTINO" ] && [ ! -f "$DESTINO/ARCHIVO.txt" ]; then
        aviso "Respaldo incompleto. Se elimina $DESTINO para que no se use por error."
        rm -rf "$DESTINO"
    fi
}
trap limpiar EXIT

# --- Paso 1: detener los escritores ------------------------------------------
# Sin esto la copia de /var/lib/rspamd puede quedar a medio escribir y el
# archivo de bayes sale corrupto. Rspamd es el unico escritor de ese volumen.
info "Deteniendo $SERVICIO_RSPAMD para obtener una copia coherente."
docker compose stop "$SERVICIO_RSPAMD" >/dev/null

# --- Paso 2: volcar Redis a disco --------------------------------------------
# SAVE es sincrono y bloquea Redis hasta terminar: es lo que garantiza que el
# dump.rdb esté consistente en vez de "casi consistente".
info "Volcando el estado de $SERVICIO_REDIS a disco."
if docker compose exec -T "$SERVICIO_REDIS" redis-cli SAVE >/dev/null 2>&1; then
    info "Redis confirmo el guardado."
else
    error "Redis no pudo guardar. El respaldo de Redis no seria coherente."
    error "Revise el estado del servicio antes de seguir."
    exit "$E_FALLO_RESPALDO"
fi

# --- Paso 3: preparar el destino ---------------------------------------------
mkdir -p "$DESTINO/datos" "$DESTINO/redis" "$DESTINO/config"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; limpiar' EXIT

# --- Paso 4: copiar el volumen de Rspamd -------------------------------------
# `docker cp` funciona con contenedores detenidos, que es justo nuestro caso.
info "Copiando $VOLUMEN_RSPAMD desde el contenedor."
if ! docker cp "$CID_RSPAMD:$VOLUMEN_RSPAMD/." "$DESTINO/datos/" 2>/dev/null; then
    error "No se pudo copiar $VOLUMEN_RSPAMD."
    exit "$E_FALLO_RESPALDO"
fi

# --- Paso 5: copiar el dump de Redis ----------------------------------------
info "Copiando $VOLUMEN_REDIS desde el contenedor."
if ! docker cp "$CID_REDIS:$VOLUMEN_REDIS/dump.rdb" "$DESTINO/redis/dump.rdb" 2>/dev/null; then
    error "No se encontro dump.rdb en Redis."
    exit "$E_FALLO_RESPALDO"
fi

# --- Paso 6: copiar la configuracion ------------------------------------------
if [ -d "$RAIZ_KIT/config/local.d" ]; then
    info "Copiando config/local.d."
    cp -a "$RAIZ_KIT/config/local.d/." "$DESTINO/config/"
else
    aviso "No existe config/local.d; se sigue sin copia de configuracion."
    mkdir -p "$DESTINO/config"
fi

# --- Paso 7: manifiesto y sumas de verificacion -------------------------------
# Se recorre el contenido excluyendo el propio manifiesto y las sumas, para que
# no se intente verificar un archivo que todavia no existe.
info "Calculando sumas SHA-256."
( cd "$DESTINO" && find . -type f \
    ! -name 'MANIFIESTO.txt' \
    ! -name 'CHECKSUMS.sha256' \
    ! -name 'ARCHIVO.txt' \
    -print0 | sort -z | xargs -0 sha256sum ) > "$TMP/CHECKSUMS.sha256"
mv "$TMP/CHECKSUMS.sha256" "$CHECKSUMS"

TOTAL_ARCHIVOS="$(find "$DESTINO" -type f | wc -l | tr -d ' ')"
TOTAL_BYTES="$(du -sb "$DESTINO" | cut -f1)"

{
    echo "MANIFIESTO DE RESPALDO — $KIT_ID"
    echo "============================================================"
    echo "Generado:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Host:          $(hostname)"
    echo "Contenido:     datos/ (volumen $VOLUMEN_RSPAMD), redis/, config/"
    echo "Archivos:      $TOTAL_ARCHIVOS"
    echo "Bytes totales: $TOTAL_BYTES"
    echo "Host de origen:"
    docker inspect -f '  rspamd: {{.Config.Image}}' "$CID_RSPAMD"
    docker inspect -f '  redis:  {{.Config.Image}}' "$CID_REDIS"
    echo
    echo "VERIFICACION DE INTEGRIDAD"
    echo "------------------------------------------------------------"
    echo "Desde el directorio del respaldo:"
    echo "    sha256sum -c CHECKSUMS.sha256"
    echo "El archivo ARCHIVO.txt marca este respaldo como completo."
    echo "Si ARCHIVO.txt no existe, el respaldo esta a medias: NO lo use."
    echo
    echo "QUE CONTIENE"
    echo "------------------------------------------------------------"
    echo "datos/     Claves DKIM privadas, archivos de bayes, mapas"
    echo "           aprendidos y cache. Es lo que NO se regenera."
    echo "redis/     dump.rdb con los clasificadores bayes, el greylist,"
    echo "           el historial y los limites de tasa."
    echo "config/    config/local.d, la configuracion del cliente."
    echo
    echo "QUE NO CONTIENE Y POR QUE"
    echo "------------------------------------------------------------"
    echo "Firmas de ClamAV   Se redescargan solas al arrancar clamav."
    echo "                    Respaldarlas cuesta gigabytes y no aporta."
    echo "Imagenes Docker    Se vuelven a descargar del registro."
    echo "Archivo .env       Sin secretos y ademas versionado en git."
    echo
    echo "SEGURIDAD DEL ARCHIVO"
    echo "------------------------------------------------------------"
    echo "Este archivo CONTIENE SECRETOS: claves privadas DKIM y el hash"
    echo "de la contrasena de la interfaz web. Quien tenga el .tar.gz"
    echo "puede firmar correo como el cliente. Guardelo con la misma"
    echo "custodia que la copia del correo y borre las copias viejas."
    echo
    echo "RESTAURAR"
    echo "------------------------------------------------------------"
    echo "    sudo ./scripts/restore-rspamd.sh $ARCHIVO_FINAL"
    echo
} > "$MANIFIESTO"

# --- Paso 8: comprimir --------------------------------------------------------
info "Comprimiendo. El volumen de bayes puede pesar bastante la primera vez."
tar -czf "$TMP/$NOMBRE.tar.gz" -C "$RUTA_BASE" "$NOMBRE"
mv "$TMP/$NOMBRE.tar.gz" "$ARCHIVO_FINAL"

# --- Paso 9: marcar como completo (SIEMPRE al final) -------------------------
# Si el script muere antes de esta linea, la trampa limpia el directorio y no
# queda un respaldo a medias que alguien pueda restaurar por error.
( cd "$DESTINO" && printf 'COMPLETO\nGenerado: %s\nArchivo: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$ARCHIVO_FINAL" > 'ARCHIVO.txt' )

SUMA_ARCHIVO="$(sha256sum "$ARCHIVO_FINAL" | cut -d' ' -f1)"
printf '%s  %s\n' "$SUMA_ARCHIVO" "$(basename "$ARCHIVO_FINAL")" > "$ARCHIVO_FINAL.sha256"

# --- Epilogo ------------------------------------------------------------------
trap - EXIT
rm -rf "$TMP"
limpiar
trap - EXIT

info "Respaldo completado."
info "  Archivo:   $ARCHIVO_FINAL"
info "  Tamano:    $TOTAL_BYTES bytes en $TOTAL_ARCHIVOS archivos"
info "  Suma:      $SUMA_ARCHIVO"
info "Guarde el archivo .sha256 junto al .tar.gz: al restaurarlo se comprueba."
exit "$E_OK"