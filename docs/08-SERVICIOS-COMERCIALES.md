# 08 — Servicios comerciales

Qué se puede vender, qué no, y qué límites tiene el producto.

---

## A quién le sirve

### Sí le sirve

**Una Pyme que tiene servidor de correo propio y hoy filtra mal.** El cliente
típico:

- 5 a 50 empleados.
- Tiene su propio dominio y su propio servidor de correo (o lo quiere
  contratar).
- Hoy usa un filtro limitado, uno gratuito que ya no da abasto, o directamente
  **ninguno**.
- Recibe spam que llega a las bandejas de los clientes.
- Sale correo que los receptores mandan a spam.
- No tiene a nadie dedicado a esto: alguien le da una mirada al panel de vez en
  cuando.

### No le sirve

| Situación | Por qué no |
|---|---|
| Usa Google Workspace, Microsoft 365 o Zoho | Ya tiene filtro. Rspamd no se puede poner delante sin romperlo. |
| No tiene servidor de correo | Este kit es solo el filtro. Falta la pieza principal. |
| Necesita apenas filtrar 5 usuarios | El costo de administrar el servidor no lo justifica. Un plan de correo gestionado sale más barato. |
| Necesita archivo legal de correo, DLP o cifrado | Eso es otra categoría de producto. |
| Es una empresa grande con TI propia | Atiende su propio ciclo de vida. No es el cliente objetivo. |

> **La honestidad de este documento existe para proteger al cliente y a
> Hefesto.** Decirle que no a un cliente que no Calza es parte del servicio.

---

## Qué se puede vender

### 1. Implementación

Puesta en marcha del kit: instalación, configuración, lista blanca inicial,
integración con Postfix y DKIM.

**Es el servicio principal.** El software es gratis (Apache 2.0); lo que se
cobra es el trabajo de dejarlo andando.

### 2. Plan de mantenimiento

Servicio mensual que incluye:

| Incluido | Detalle |
|---|---|
| Supervision | Revisión del estado de los contenedores |
| Actualizaciones controladas | Con respaldo previo y ventana acordada |
| Ajuste de la lista blanca | Cuando el cliente avisa que no llegó algo |
| Revisión mensual | Estadísticas, falsos positivos, proposals de ajuste |
| Respaldo verificado | Ejecución y comprobación del script |

### 3. Revisión de seguridad de correo

Revisión puntual de la configuración DMARC, SPF y DKIM, y de la reputación de
la IP del cliente.

### 4. Sesión de capacitación

Para que el cliente sepa:

- qué es un falso positivo y por qué va a ocurrir;
- cómo agregar un remitente a la lista blanca;
- qué mirar en la interfaz web;
- cuándo llamar.

---

## Qué se puede cobrar, en la práctica

El software no tiene costo de licencia. **El precio lo define el trabajo.**

El factor de costo más visible para el cliente:

| Recurso | Con antivirus | Sin antivirus |
|---|---|---|
| RAM del servidor | 4 GB mínimo, 8 GB recomendado | 2 GB |
| Disco | 20 GB | 10 GB |

Una Pyme que quiere ClamAV tiene que **agrandar su servidor**. Eso es un costo
directo y hay que decirlo antes de firmar, no después.

---

## Límites del producto: lo que NO se puede prometer

Esta es la sección más importante del documento.

### 1. No se puede prometer "cero falsos positivos"

**No existe un filtro de correo electrónico que no tire correo bueno.** Quien
lo prometa está mintiendo, y el cliente lo va a descubrir en la primera semana,
cuando falte un correo de un cliente de su Pyme.

**En su lugar, prometa el proceso:** lista blanca medida, revisión semanal y
reversión en menos de diez minutos.

### 2. No se puede prometer un porcentaje de falso positivo

No hay una cifra universal. Depende del volumen, de la lista blanca inicial y
del greylisting.

**Si el cliente insiste en un número, la respuesta honesta es:** "no se lo puedo
dar antes de medirlo en su servidor. Lo que sí hago es medirlo con usted desde
la primera semana y reportarle todas las semanas".

### 3. No se puede prometer que Rspamd resuelve la suplantación

Rspamd filtra **correo que entra**. **DKIM** firma correo que sale. Son dos
cosas distintas.

El fraude de suplantación de dominio se resuelve con **SPF, DKIM y DMARC
configurados correctamente y con `p=quarantine` o `p=reject`**. Eso es trabajo
de configuración de DNS, y este kit cubre solo la parte de DKIM.

### 4. No se puede prometer que el antivirus es infalible

ClamAV es **una** capa. Hay malware que no detecta, y hay Emails que no llevan
archivo adjunto sino un enlace malicioso, que el antivirus no va a ver.

### 5. No se puede prometer que el correo va a llegar siempre

Greylisting, listas negras mal configuradas, reputación de IP y un sinfín de
factores afectan la entregabilidad. **DKIM ayuda, pero no garantiza.**

### 6. No se puede prometer soporte 24/7

Verificar el horario de soporte antes de venderlo.

---

## Responsabilidad: qué es del cliente y qué es de Hefesto

Este reparto debe quedar **por escrito** antes de empezar.

### Del cliente

- El **servidor de correo** (Postfix, Dovecot, sistema operativo, parches).
- Los **registros DNS** del dominio.
- Las **cuentas de correo** y sus contraseñas.
- El **contraseña de Rspamd** (Hefesto la configura, el cliente la custodia).
- **Publicar los registros DKIM.** Hefesto indica el contenido; el cliente lo
  publica, porque solo el cliente controla la zona.
- **Avisar cuando no llega un correo importante.**

### De Hefesto

- La instalación y configuración de Rspamd.
- La integración con Postfix según la versión que el cliente indique.
- La carga inicial de la lista blanca.
- La configuración de DKIM y la entrega del contenido del registro TXT.
- El mantenimiento y las actualizaciones, si contrató el plan.
- El respaldo, si contrató el plan.

### Zona gris que conviene aclarar por escrito

- **Registrars que filtran antes de Rspamd.** Si el Hosting rechaza el correo
  entrante, Rspamd ni lo ve.
- **Antispam del proveedor de salida.** Si el cliente envía por un servicio
  externo, la firma DKIM la agrega ese servicio, no Rspamd.
- **Cambios en el servidor del cliente** que rompan la integración y que no se hayan anotado.

---

## Sobre el uso de la marca y del nombre

- Hefesto **no** vende el producto como "Rspamd". El nombre comercial es propio.
- En la documentación técnica **sí** se nombra Rspamd, que es lo correcto y lo
  que pide la atribución de Apache 2.0.
- **No** usar el logotipo de Rspamd en material comercial.
- Decir "**basado en** Rspamd" o "**con** Rspamd" es correcto. Decir "sistema
  antispam Rspamd de Hefesto" es ambiguo y mejor evitarlo.

---

## El argumento de venta honesto

> "Su correo entra por su servidor y llega a las bandejas de sus clientes.
> Rspamd revisa cada mensaje antes de entregarlo: lista negra, heurísticas,
> clasificación por aprendizaje y una lista blanca de sus clientes y
> proveedores. Además, su correo saliente queda firmado con DKIM, que es lo
> que hoy le está haciendo llegar a spam afuera.
>
> No es perfecto —ningún filtro de correo lo es— y va a descartar algún correo
> legítimo. Por eso lo medimos: usted ve todas las semanas cuántos correos
> buenos se perdieron y quién, y se Patti al instante. Ese es el servicio."

---

## Lo que hay que tener claro antes de vender

- [ ] El cliente tiene servidor de correo propio. **Confirmado por escrito.**
- [ ] El cliente controla sus registros DNS. **Confirmado.**
- [ ] El cliente entiende que habrá falsos positivos. **Confirmado.**
- [ ] Si hay antivirus, el servidor tiene la RAM. **Confirmado.**
- [ ] El reparto de responsabilidades está por escrito.
- [ ] El horario de soporte está escrito.
- [ ] Nadie prometió un porcentaje de falso positivo.