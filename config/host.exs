import Config

# En las pruebas el registro se escribe en una carpeta temporal distinta en cada
# ejecución, para que un documento viejo no contamine los resultados.
directorio =
  if config_env() == :test do
    Path.join(System.tmp_dir!(), "documento_prueba_#{System.unique_integer([:positive])}")
  else
    "datos"
  end

config :documento, directorio_datos: directorio

config :nerves_runtime,
  kv_backend:
    {Nerves.Runtime.KVBackend.InMemory,
     contents: %{
       "nerves_fw_active" => "a",
       "a.nerves_fw_architecture" => "generic",
       "a.nerves_fw_description" => "N/A",
       "a.nerves_fw_platform" => "host",
       "a.nerves_fw_version" => "0.0.0"
     }}
