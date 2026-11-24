import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
config :nerves, source_date_epoch: "1795044054"

# Nodos a los que se conecta de forma explícita (ip1,ip2). Se lee al compilar:
#   DOC_NODOS="172.20.10.4,172.20.10.5" mix firmware
nodos =
  case System.get_env("DOC_NODOS") do
    nil -> []
    texto -> Enum.map(String.split(texto, ",", trim: true), fn ip -> String.trim(ip) end)
  end

# Modo transitivo del paper (ti): cada nodo reenvía lo nuevo que recibe. En la malla
# completa de Erlang no hace falta; sirve si no todos los nodos se ven entre sí.
#   DOC_REENVIAR=true mix firmware
config :documento,
  nodos: nodos,
  reenviar: System.get_env("DOC_REENVIAR") == "true",
  intervalo_estado_completo: 30_000

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
