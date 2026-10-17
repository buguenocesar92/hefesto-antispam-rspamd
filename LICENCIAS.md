# Licencias de los componentes

Este kit se distribuye como servicio de Hefesto Studio y **no cambia la licencia
de ningún componente de terceros**. Todo lo que instala sigue bajo la licencia
del proyecto original.

---

## Resumen

| Componente | Licencia | Enlace oficial |
|---|---|---|
| **Rspamd** | **Apache License 2.0** | <https://github.com/rspamd/rspamd/blob/4.2.2/LICENSE.md> |
| **Redis** | BSD de 3 cláusulas | <https://github.com/redis/redis/blob/unstable/COPYING> |
| **ClamAV** | GPL-2.0 | <https://github.com/Cisco-Talos/clamav/blob/main/COPYING> |
| Docker Compose / Docker Engine | Apache 2.0 (Docker) y componentes con licencias propias | <https://github.com/moby/moby/blob/master/LICENSE> |

---

## Rspamd — Apache License 2.0

**Este es el dato que más se corrige.** Rspamd se distribuye—hecho
verificado— bajo **Apache License 2.0**, y **no** bajo una licencia tipo BSD.

### Cómo se verificó

Tres fuentes independientes coinciden:

1. **El archivo de licencia del propio repositorio**, etiqueta `4.2.2`:
   <https://raw.githubusercontent.com/rspamd/rspamd/4.2.2/LICENSE.md>
2. **Las cabeceras de los archivos fuente.** Todos los archivos `.c` y `.cxx`
   del proyecto abren con el encabezado completo de Apache 2.0. Por ejemplo
   `src/rspamd.c` en la etiqueta `4.2.2`.
3. **La documentación y el perfil oficial de Docker Hub** de `rspamd/rspamd`,
   que declara Apache 2.0.

> Nota técnica: la API de licencias de GitHub devuelve `NOASSERTION` para este
> repositorio porque el archivo se llama `LICENSE.md` y no `LICENSE`, y porque
> trae una línea de encabezado adicional. El **texto** es el de Apache 2.0 y
> las cabeceras de los fuentes lo confirman.

### Qué obliga Apache 2.0

- **Atribución.** Hay que indicar que Rspamd se usa, y mantener los avisos de
  copyright en los archivos que se redistribuyan.
- **Mantener las licencias y los avisos** de los archivos originales.
- **Declarar las modificaciones** que se hayan hecho al código.
- **Permite uso comercial.** No hay copyleft: usar Rspamd en un servicio de
  pago para una Pyme no obliga a publicar nada.
- **No hay garantía.** El software se entrega "tal cual".

### Aviso de marca

Rspamd es una marca de sus autores. Hefesto Studio **no** usa "Rspamd" como
nombre del producto que vende. El nombre comercial del servicio es propio; en
la documentación técnica se nombra Rspamd para identificar el componente, que es
lo correcto y lo que pide la atribución.

---

## Redis — BSD de 3 cláusulas

Permite uso comercial. Obliga a mantener el aviso de copyright y a no usar el
nombre de Redis parapio sin permiso. No obliga a publicar código derivado.

Versión exacta usada por el kit: `redis:8.10.2`.

---

## ClamAV — GPL-2.0

ClamAV es software libre bajo GPL versión 2.

### Qué significa esto en la práctica para Hefesto Studio

- **Uso en servidor, sin distribución:** no hay problema. Un servicio que
  ejecuta ClamAV en el servidor del cliente no está distribuyendo ClamAV.
- **No se modifica el código** de ClamAV en este kit. Se usa la imagen oficial
  sin parches. Eso evita cualquier obligación de publicar código derivado.
- **No se distribuye ClamAV dentro de otro producto cerrado.** ClamAV se
  descarga desde Docker Hub en el servidor del cliente.
- **El módulo `antivirus` de Rspamd habla con `clamd` por red** (puerto 3310).
  Es una interfaz entre procesos y programas independientes, no una incorporación
  de ClamAV dentro de Rspamd.

---

## Licencia de este kit

Los archivos propios de Hefesto Studio de este kit —los `.md`, los scripts y
los comentarios de configuración— son material de trabajo del estudio. El
cliente los recibe como parte del servicio contratado.

Los componentes de terceros **no** se incluyen en el paquete: se descargan en
el momento de desplegar.

---

## Cómo citar esto correctamente en una propuesta comercial

> "El filtrado se realiza con **Rspamd**, un proyecto de código abierto bajo
> **licencia Apache 2.0**, que permite uso comercial sin costo de licencia por
> usuario. La administración, la puesta en marcha y el soporte los entrega
> Hefesto Studio."

**Incorrecto:** "Rspamd es BSD." No lo es.

---

## Obligación práctica que sí nos toca

Al entregar el servicio hay que poder mostrar de dónde salió cada componente.
Para eso están:

- `VERSION.md`, con versiones, digests y enlaces de origen.
- `docs/10-LICENCIAS-Y-FUENTES.md`, con el detalle de cada componente.

Además, `scripts/backup-rspamd.sh` escribe un `MANIFIESTO.txt` dentro de cada
respaldo que registra las imágenes exactas del servidor de origen, de modo que
quien restituya un respaldo meses después sabe con qué versiones se generó.

Revise `docs/10-LICENCIAS-Y-FUENTES.md` antes de publicar cualquier material
del cliente donde se muestren capturas de la interfaz de Rspamd.