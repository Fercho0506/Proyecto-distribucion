defmodule Documento.Almacenamiento do
  require Logger

  def ruta() do
    directorio = Application.get_env(:documento, :directorio_datos, "datos")
    Path.join([directorio, "documento", "registro.log"])
  end

  def abrir() do
    ruta = ruta()

    case File.mkdir_p(Path.dirname(ruta)) do
      :ok ->
        cortada = linea_cortada(ruta)

        case File.open(ruta, [:append, :binary, :raw]) do
          {:ok, archivo} ->
            if cortada do
              :file.write(archivo, "\n")
            end

            {:ok, archivo}

          {:error, razon} ->
            Logger.error("[documento] no se pudo abrir #{ruta}: #{inspect(razon)}")
            :error
        end

      {:error, razon} ->
        Logger.error("[documento] no se pudo crear la carpeta de #{ruta}: #{inspect(razon)}")
        :error
    end
  end

  def guardar(nil, _mensaje) do
    :error
  end

  def guardar(archivo, mensaje) do
    linea = Base.encode64(:erlang.term_to_binary(mensaje)) <> "\n"

    case :file.write(archivo, linea) do
      :ok ->
        case :file.sync(archivo) do
          :ok -> :ok
          {:error, razon} -> fallo_de_escritura(razon)
        end

      {:error, razon} ->
        fallo_de_escritura(razon)
    end
  end

  def guardar_varios(nil, _mensajes), do: {:error, :archivo_no_disponible}
  def guardar_varios(_archivo, []), do: :ok

  def guardar_varios(archivo, mensajes) do
    lineas = Enum.map(mensajes, fn mensaje -> Base.encode64(:erlang.term_to_binary(mensaje)) <> "\n" end)

    case :file.write(archivo, lineas) do
      :ok ->
        case :file.sync(archivo) do
          :ok -> :ok
          {:error, razon} -> fallo_de_escritura(razon)
        end
      {:error, razon} -> fallo_de_escritura(razon)
    end
  end

  def cargar() do
    case File.read(ruta()) do
      {:ok, contenido} ->
        lineas = String.split(contenido, "\n", trim: true)
        Enum.flat_map(lineas, fn linea -> decodificar(linea) end)

      {:error, _razon} ->
        []
    end
  end

  defp decodificar(linea) do
    case Base.decode64(linea) do
      {:ok, binario} ->
        try do
          [:erlang.binary_to_term(binario)]
        rescue
          _ -> []
        end

      :error ->
        []
    end
  end

  defp linea_cortada(ruta) do
    case File.read(ruta) do
      {:ok, ""} -> false
      {:ok, contenido} -> not String.ends_with?(contenido, "\n")
      {:error, _razon} -> false
    end
  end

  defp fallo_de_escritura(razon) do
    Logger.error("[documento] no se pudo escribir el registro: #{inspect(razon)}")
    :error
  end
end
