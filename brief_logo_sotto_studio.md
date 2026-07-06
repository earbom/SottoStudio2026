# Brief de diseño — Icono/logo de Sotto Studio

## Encargo
Diseñar un icono que sea a la vez:
1. Reconocible como una **efe de violín (f-hole)** — la abertura acústica tallada en la tapa de instrumentos de la familia del violín.
2. Reconocible como una **letra S** — inicial de "Sotto Studio".

No es una elección estética libre: la app registra práctica instrumental, así que el f-hole ancla la marca al mundo real de la música de cuerda, mientras que la S la ancla al nombre del producto.

## Por qué los intentos anteriores no funcionaron
Se probaron varias direcciones (clave de sol de referencia, S geométrica con guiños de clave, clave de sol inclinada, S como onda de sonido con barras de amplitud, S con ojos y muescas de f-hole) y ninguna cuajó porque no partían de la anatomía real del f-hole, sino de una S genérica a la que se le añadían elementos musicales sueltos. El resultado se leía como "S decorada", no como f-hole.

## Anatomía de referencia (a partir de la foto de f-hole real aportada)
El f-hole tiene, de arriba abajo:

1. **Voluta superior**: un círculo pequeño casi cerrado en la parte alta, como el principio de un caracol — no es una curva abierta, es un bucle que casi se toca a sí mismo.
2. **Caña superior**: un trazo grueso y curvado que desciende desde la voluta, inclinándose hacia el centro del instrumento.
3. **Muescas laterales (las "orejas")**: dos pequeñas protuberancias triangulares a media altura, una a cada lado del trazo principal, justo donde iría el puente del instrumento. Son el detalle que más "vende" que es un f-hole y no una S cualquiera.
4. **Cintura central**: el trazo se estrecha ligeramente en el punto de las muescas, como una cintura de reloj de arena muy sutil.
5. **Caña inferior**: simétrica a la superior en proporción pero más larga, ensanchándose de nuevo hacia abajo.
6. **Círculo inferior**: un círculo relleno (no un bucle abierto como el de arriba) — un punto sólido y redondo que cierra la composición.

La curva completa, de voluta a círculo inferior, ya dibuja una S estirada y esbelta de forma natural — ahí está la coincidencia entre f-hole y S que hay que explotar, no forzar.

## Instrucciones concretas para el diseño

- **Partir de la silueta real del f-hole**, no de una S a la que se le añaden detalles. La legibilidad como S debe salir de estirar/estilizar el f-hole, no de partir de una S e insertarle ojos.
- **Mantener las dos muescas laterales**: son el elemento más distintivo y no deben eliminarse ni suavizarse hasta desaparecer, aunque se simplifiquen para verse bien a tamaño pequeño (favicon, icono de app).
- **Diferenciar claramente el remate superior (bucle/voluta) del remate inferior (círculo sólido)** — no hacerlos iguales, esa asimetría es parte de lo que hace reconocible un f-hole real.
- **Grosor de trazo constante o con variación sutil** (más grueso en la cintura central, más fino en los extremos), no un trazo uniforme tipo tubería.
- El icono debe funcionar en:
  - **Monocromo** (un solo color, para favicon/iconos de sistema).
  - **A tamaño pequeño** (24×24 px aprox., como icono de pestaña o notificación) sin perder las muescas.
  - **Como parte de la wordmark completa**: a la izquierda del texto "otto STUDIO" (ver más abajo).

## Paleta
- **Navy**: `#16283D` (fondo oscuro / texto principal sobre claro)
- **Naranja acento**: `#E07A2C` sobre fondos claros, `#F0954A` sobre fondos oscuros
- **Crema**: `#F5F1E8` (fondo claro / texto sobre oscuro)

## Tipografía
**Poppins**, para toda la wordmark.

## Composición de la wordmark
- Icono (el f-hole/S) a la izquierda.
- Texto "otto" en el color principal (navy sobre fondo claro, crema sobre fondo oscuro).
- Debajo, "STUDIO" en naranja acento, con tracking (espaciado entre letras) notablemente más ancho que "otto", en un tamaño de fuente menor.
- El logo existente del centro ("oh" amarillo mostaza sobre negro + "HARO ESTUDIS MUSICALS" en Poppins, jerarquía HARO grande + ESTUDIS MUSICALS con espaciado ancho) es un elemento **ya cerrado y no se toca** — el logo de Sotto Studio es una marca hermana, no tiene que imitar sus colores, pero sí puede compartir la lógica tipográfica de jerarquía (palabra grande + subtítulo con tracking ancho), ya que ambas marcas conviven en la misma app.

## Entregables esperados
- Versión del icono en SVG vectorial limpio (path único o mínimo de paths).
- Versión monocromo para favicon/icono de app (adaptada si las muescas se pierden a tamaño mínimo).
- Wordmark completa (icono + "otto STUDIO") en SVG, en versión fondo claro y versión fondo oscuro.
- Si se generan variantes, priorizar aquellas donde el f-hole se reconozca primero como f-hole (para quien conoce instrumentos de cuerda) y como S en una segunda lectura (para el resto de usuarios) — no al revés.
