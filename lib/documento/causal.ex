defmodule Documento.Causal do

  @max_espera 50_000

  def siguiente(vector, autor) do
    seq = Map.get(vector, autor, 0) + 1
    {seq, Map.put(vector, autor, seq)}
  end

  def clasificar(vector, %{from: autor, vc: recibido}) do
    seq_recibido = Map.get(recibido, autor, 0)
    seq_local = Map.get(vector, autor, 0)

    cond do
      seq_recibido <= seq_local -> :duplicada
      seq_recibido == seq_local + 1 and dependencias_listas?(vector, autor, recibido) -> :entregable
      true -> :espera
    end
  end

  def entregar(vector, %{from: autor, vc: recibido}) do
    Map.put(vector, autor, Map.fetch!(recibido, autor))
  end

  def recibir(vector, espera, operacion) do
    case clasificar(vector, operacion) do
      :duplicada -> {vector, espera, [], :duplicada}
      :espera -> {vector, guardar(espera, operacion), [], :espera}
      :entregable ->
        {vector, espera, aplicadas} = vaciar(entregar(vector, operacion), espera, [operacion])
        {vector, espera, aplicadas, :aplicada}
    end
  end

  def faltan(vector, %{from: autor, vc: recibido}) do
    Enum.reduce(recibido, %{}, fn {nodo, seq}, faltantes ->
      requerido = if nodo == autor, do: seq - 1, else: seq
      if requerido > Map.get(vector, nodo, 0), do: Map.put(faltantes, nodo, requerido), else: faltantes
    end)
  end

  defp dependencias_listas?(vector, autor, recibido) do
    Enum.all?(recibido, fn {nodo, seq} -> nodo == autor or seq <= Map.get(vector, nodo, 0) end)
  end

  defp guardar(espera, operacion) do
    repetida? = Enum.any?(espera, fn otra -> misma?(otra, operacion) end)
    if repetida? or length(espera) >= @max_espera, do: espera, else: [operacion | espera]
  end

  defp vaciar(vector, espera, aplicadas) do
    espera = Enum.reject(espera, &(clasificar(vector, &1) == :duplicada))

    case Enum.find(espera, &(clasificar(vector, &1) == :entregable)) do
      nil -> {vector, espera, Enum.reverse(aplicadas)}
      operacion -> vaciar(entregar(vector, operacion), List.delete(espera, operacion), [operacion | aplicadas])
    end
  end

  defp misma?(a, b), do: a.from == b.from and Map.get(a.vc, a.from) == Map.get(b.vc, b.from)
end
