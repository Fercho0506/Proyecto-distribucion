# Documento distribuido (Elixir / Nerves)

Implementación de un documento colaborativo sin servidor central. Cada Raspberry Pi mantiene una réplica local completa y se comunica con las demás mediante broadcast sobre Erlang Distribution.

## Requisitos del enunciado

- **Task 1 — descubrimiento:** `Documento.Descubrimiento` conecta nodos `doc@IP` mediante barrido de la subred y admite conexión explícita. `Documento.Red` inicia la distribución Erlang en Nerves cuando la Raspberry Pi obtiene su IP.
- **Task 1 — broadcast:** `Documento.Difusion` es el punto único de salida y envía cada mensaje a todos los nodos de `Node.list()`.
- **Task 2 — CRDT:** `Documento.Treedoc` conserva posiciones estables y tombstones. `Documento.Mensaje` valida operaciones compatibles con el protocolo de integración.
- **Concurrencia:** `Documento.Causal` usa relojes vectoriales, detecta duplicados y retiene temporalmente operaciones cuyas dependencias aún no han llegado.
- **Recuperación:** `Documento.Almacenamiento` persiste el historial de operaciones; al reiniciar se reconstruyen el documento y el reloj.

## Uso en modo host

En cada computador, usa una IP distinta de la misma red:

```sh
mix deps.get
MIX_TARGET=host mix test
MIX_TARGET=host iex --name doc@172.20.10.3 --cookie cpd2026 --erl "-kernel prevent_overlapping_partitions false inet_dist_listen_min 4218 inet_dist_listen_max 4228" -S mix
```

En otro equipo:

```sh
MIX_TARGET=host iex --name doc@172.20.10.4 --cookie cpd2026 --erl "-kernel prevent_overlapping_partitions false inet_dist_listen_min 4218 inet_dist_listen_max 4228" -S mix
```

Desde IEx:

```elixir
Documento.conectar("172.20.10.4")
Documento.insertar(0, "Hola mundo")
Documento.borrar(5, 1)
Documento.texto()
Documento.nodos()
Documento.estado()
Documento.historial()
Documento.sincronizar()
```

En Raspberry Pi el nombre de nodo incluye hostname y una época persistente (`hostname-epoca@IP`), para que borrar el registro no reutilice secuencias anteriores. El descubrimiento automático recorre direcciones útiles de la subred cada 10 segundos y consulta EPMD para detectar nombres de nodo de ambos proyectos (no solo `doc@IP`). La conexión explícita acepta una IP o el nombre completo del nodo. La conexión a un par hace que la distribución Erlang complete la malla. La configuración de la VM desactiva el corte de enlaces no relacionados cuando cae una conexión, porque no usamos nombres globales.

## Raspberry Pi (Nerves)

Configura las variables de entorno del sistema Nerves como en la configuración original del proyecto:

```sh
export MIX_TARGET=rpi4
export HOTSPOT_SSID="nombre-de-la-red"
export HOTSPOT_PSK="clave-de-la-red"
export DOC_NODOS="172.20.10.4,172.20.10.5" # opcional
mix deps.get
mix firmware
mix burn
```

Para conservar el registro de operaciones, usa el procedimiento de actualización que no borre `/root`; `mix burn` puede eliminar los datos persistentes según el medio y la configuración.

## Arquitectura

```text
Documento.Aplicacion
├── Documento.Red             (solo Nerves)
├── Documento.Replica         proceso distribuido Crdt.Replica
└── Documento.Descubrimiento  búsqueda y conexión de pares

Documento.Treedoc       CRDT de posiciones / tombstones
Documento.Causal        reloj vectorial y entrega causal
Documento.Mensaje       validación del protocolo compartido
Documento.Difusion      broadcast a todos los nodos conectados
Documento.Almacenamiento registro persistente de operaciones
```

## Compatibilidad

La compatibilidad de red se basa en el contrato compartido: proceso `Crdt.Replica`, cookie `cpd2026`, nodos `doc@IP`, operaciones `:ins` / `:del`, reloj vectorial y posids `{bit, secuencia, nodo}`. La API pública de este proyecto conserva el módulo `Documento`; el proyecto de referencia usa su propio módulo de API. No se intercambian estados completos v1 como mecanismo normal de sincronización.

## Cambio desde el formato anterior

La versión anterior del proyecto guardaba estados completos con otro formato de PosID. Ese registro no es interoperable con las operaciones de este protocolo y se ignora al reconstruir el documento. Antes de actualizar una Raspberry Pi con datos que quieras conservar, haz una copia de `datos/documento/registro.log`; el historial nuevo se crea con el formato de operaciones.

## Verificación pendiente

Ejecutar `MIX_TARGET=host mix test` y una prueba real con dos o más nodos BEAM/Raspberry Pi. El entorno de reconstrucción no tiene Elixir ni Mix instalados, por lo que no se afirma que esta versión haya compilado ni que la interoperabilidad física haya sido probada aquí.

## Prueba de interoperabilidad con `documento.zip`

1. Ejecuta `proyecto_distribucion` en una Raspberry Pi y `documento` en otra. Ambos deben usar la cookie `cpd2026` y estar en la misma red.
2. Verifica que ambos procesos estén registrados bajo el nombre distribuido `Crdt.Replica` y que `Documento.nodos()` / `CpdDoc.estado()` muestren el otro nodo.
3. En el nodo de este proyecto ejecuta `Documento.insertar(0, "desde A")`; en el otro verifica `CpdDoc.texto()`.
4. En el nodo de `documento` ejecuta `CpdDoc.insertar(0, "desde B: ")`; en este proyecto verifica `Documento.texto()`.
5. Prueba un borrado y dos inserciones concurrentes en el mismo índice. Tras recibir el historial, ambos textos deben coincidir.

Si la conexión automática no se establece, desde este proyecto ejecuta `Documento.conectar("IP_DEL_OTRO_NODO")`. Desde el proyecto de referencia se puede conectar usando el nombre completo que aparece en `Node.list()`.
