defmodule Documento.Difusion do

  def difundir(mensaje) do
    Enum.reduce(Node.list(), {0, 0}, fn nodo, {enviados, fallidos} ->
      case GenServer.cast({Documento.Mensaje.nombre(), nodo}, mensaje) do
        :ok -> {enviados + 1, fallidos}
        _ -> {enviados, fallidos + 1}
      end
    end)
  end
end
