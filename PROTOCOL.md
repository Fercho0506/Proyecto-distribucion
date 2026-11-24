# Protocolo de integración: Treedoc basado en operaciones

Este proyecto mantiene el protocolo de integración de los nodos `documento` del curso. La comunicación entre réplicas usa Erlang Distribution y mensajes broadcast a todos los nodos conectados.

## Red y descubrimiento

- Todos los equipos deben estar en la misma red local.
- Nombre del nodo: `doc@<ipv4>` (por ejemplo `doc@172.20.10.3`).
- Cookie Erlang: `cpd2026`.
- Proceso de réplica compartido: `Crdt.Replica`.
- El descubrimiento recorre la subred cada 10 segundos y consulta EPMD en cada IP para descubrir cualquier nombre de nodo anunciado (incluidos `hostname-epoca@IP` y `doc@IP`). También se permite conexión explícita por IP o por nombre completo con `Documento.conectar/1`.
- No hay servidor central: cualquier nodo puede iniciar, editar y difundir.

## Mensajes de operación

Cada edición se representa como una operación individual y se envía con `GenServer.cast({Crdt.Replica, nodo}, {:remote, operacion})` a cada nodo conectado.

Inserción:

```elixir
%{op: :ins, from: node(), vc: vector_clock, pos: posid, ch: grapheme}
```

Borrado:

```elixir
%{op: :del, from: node(), vc: vector_clock, pos: posid}
```

- `from` es el átomo del nodo que creó la operación.
- `vc` es un reloj vectorial: mapa de nodo a secuencia conocida. La secuencia propia aumenta de uno en uno.
- `posid` es una lista no vacía de `{bit, secuencia, nodo}`, con `bit` igual a `0` o `1`.
- `ch` contiene exactamente un grafema Unicode.

El mensaje remoto se encapsula como `{:remote, operacion}`. `{:hello, node()}` solicita el reenvío del historial completo. En `nodeup` y periódicamente, cada réplica vuelve a difundir su historial para reparar desconexiones.

## Causalidad y convergencia

Una operación se aplica cuando su secuencia es la siguiente esperada para su autor y todas sus dependencias del vector ya se han aplicado. Si faltan dependencias, queda temporalmente en espera. Las operaciones repetidas se descartan mediante el reloj vectorial. Las operaciones aceptadas se guardan en el registro local antes de ser difundidas o aplicadas a la vista del documento.

Cada réplica conserva el historial de operaciones y reconstruye el documento y el reloj al reiniciar. Los identificadores de posición y la regla de orden son compatibles con el proyecto de referencia `documento`.
