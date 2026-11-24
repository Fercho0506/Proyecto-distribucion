defmodule Documento.Mensaje do

  @nombre Crdt.Replica
  @max_vector 10_000
  @max_profundidad 20_000

  def nombre, do: @nombre

  def leer(%{op: :ins, from: from, vc: vc, pos: pos, ch: ch} = op) do
    if base?(from, vc, pos) and caracter?(ch) do
      {:ok, Map.take(op, [:op, :from, :vc, :pos, :ch])}
    else
      :error
    end
  end

  def leer(%{op: :del, from: from, vc: vc, pos: pos} = op) do
    if base?(from, vc, pos) do
      {:ok, Map.take(op, [:op, :from, :vc, :pos])}
    else
      :error
    end
  end

  def leer(_), do: :error

  def caracter?(ch) when is_binary(ch), do: String.valid?(ch) and String.first(ch) == ch
  def caracter?(_), do: false

  defp base?(from, vc, pos) do
    nodo?(from) and vector?(vc) and is_integer(Map.get(vc, from)) and
      Map.get(vc, from) >= 1 and is_list(pos) and pos != [] and pasos?(pos, 0)
  end

  defp nodo?(n), do: is_atom(n) and n not in [nil, true, false]

  defp vector?(vc) when is_map(vc) and map_size(vc) <= @max_vector do
    Enum.all?(vc, fn {nodo, seq} -> nodo?(nodo) and is_integer(seq) and seq >= 0 end)
  end

  defp vector?(_), do: false

  defp pasos?([], _), do: true
  defp pasos?(_, profundidad) when profundidad >= @max_profundidad, do: false

  defp pasos?([{bit, seq, nodo} | resto], profundidad)
       when bit in [0, 1] and is_integer(seq) and seq >= 1 and is_atom(nodo) do
    nodo?(nodo) and pasos?(resto, profundidad + 1)
  end

  defp pasos?(_, _), do: false
end
