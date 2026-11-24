defmodule Documento.Treedoc do
  @moduledoc "Documento Treedoc, posiciones estables y operaciones."

  def nuevo, do: %{atomos: %{}, borrados: MapSet.new()}

  def menor?([], []), do: false
  def menor?([], [{bit, _, _} | _]), do: bit == 1
  def menor?([{bit, _, _} | _], []), do: bit == 0
  def menor?([x | xs], [x | ys]), do: menor?(xs, ys)
  def menor?([x | _], [y | _]), do: x < y

  def orden(doc), do: Enum.sort(Map.to_list(doc.atomos), fn {a, _}, {b, _} -> menor?(a, b) end)
  def visibles(doc), do: Enum.reject(orden(doc), fn {pos, _} -> MapSet.member?(doc.borrados, pos) end)
  def texto(doc), do: Enum.map_join(visibles(doc), fn {_, caracter} -> caracter end)
  def menor_caracter(a, b), do: min(a, b)

  def preparar_insercion(doc, indice, caracteres, secuencia_inicial, autor) do
    ordenados = orden(doc)
    visibles = Enum.reject(ordenados, fn {pos, _} -> MapSet.member?(doc.borrados, pos) end)

    if is_integer(indice) and indice >= 0 and indice <= length(visibles) and is_list(caracteres) do
      izquierda = anterior(visibles, indice)
      derecha = siguiente(ordenados, izquierda)
      ubicaciones = balancear(Enum.with_index(caracteres, secuencia_inicial + 1), {:entre, izquierda, derecha}, autor)
      {:ok, ubicaciones |> Enum.sort_by(fn {_pos, _ch, seq} -> seq end) |> Enum.map(fn {pos, ch, _} -> {pos, ch} end)}
    else
      {:error, :posicion_invalida}
    end
  end

  def preparar_borrado(doc, indice, cantidad) do
    visibles = visibles(doc)

    if is_integer(indice) and is_integer(cantidad) and indice >= 0 and cantidad >= 0 and indice + cantidad <= length(visibles) do
      {:ok, Enum.slice(visibles, indice, cantidad) |> Enum.map(fn {pos, _} -> pos end)}
    else
      {:error, :posicion_invalida}
    end
  end

  def aplicar(doc, %{op: :ins, pos: pos, ch: caracter}) do
    %{doc | atomos: Map.update(doc.atomos, pos, caracter, &min(&1, caracter))}
  end

  def aplicar(doc, %{op: :del, pos: pos}), do: %{doc | borrados: MapSet.put(doc.borrados, pos)}

  def aplicar_todos(doc, operaciones), do: Enum.reduce(operaciones, doc, &aplicar(&2, &1))

  defp balancear([], _lugar, _autor), do: []

  defp balancear(caracteres, lugar, autor) do
    {izquierda, [{caracter, seq} | derecha]} = Enum.split(caracteres, div(length(caracteres), 2))
    pos = ubicar(lugar, seq, autor)
    [{pos, caracter, seq}] ++ balancear(izquierda, {:hijo, pos, 0}, autor) ++ balancear(derecha, {:hijo, pos, 1}, autor)
  end

  defp ubicar({:entre, izquierda, nil}, seq, autor), do: izquierda ++ [{1, seq, autor}]

  defp ubicar({:entre, izquierda, derecha}, seq, autor) do
    if prefijo?(derecha, izquierda), do: derecha ++ [{0, seq, autor}], else: izquierda ++ [{1, seq, autor}]
  end

  defp ubicar({:hijo, padre, bit}, seq, autor), do: padre ++ [{bit, seq, autor}]

  defp prefijo?(_lista, []), do: true
  defp prefijo?([x | xs], [x | ys]), do: prefijo?(xs, ys)
  defp prefijo?(_, _), do: false

  defp anterior(_visibles, 0), do: []
  defp anterior(visibles, indice), do: visibles |> Enum.at(indice - 1) |> elem(0)

  defp siguiente([], _izquierda), do: nil
  defp siguiente([{pos, _} | _], []), do: pos
  defp siguiente(ordenados, izquierda) do
    case Enum.drop_while(ordenados, fn {pos, _} -> pos != izquierda end) do
      [_, {siguiente, _} | _] -> siguiente
      _ -> nil
    end
  end
end
