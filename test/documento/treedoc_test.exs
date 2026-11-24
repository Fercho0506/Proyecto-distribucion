defmodule Documento.TreedocTest do
  use ExUnit.Case, async: true
  alias Documento.Treedoc

  defp insertar(doc, texto, indice \\ 0, autor \\ :autor) do
    caracteres = String.graphemes(texto)
    {:ok, posiciones} = Treedoc.preparar_insercion(doc, indice, caracteres, 0, autor)

    operaciones =
      Enum.map(posiciones, fn {pos, ch} ->
        seq = pos |> List.last() |> elem(1)
        %{op: :ins, from: autor, vc: %{autor => seq}, pos: pos, ch: ch}
      end)

    {Treedoc.aplicar_todos(doc, operaciones), operaciones}
  end

  test "inserción de texto y borrado de rango mantienen el orden visible" do
    {doc, _} = insertar(Treedoc.nuevo(), "Hola mundo")
    assert Treedoc.texto(doc) == "Hola mundo"
    {:ok, posiciones} = Treedoc.preparar_borrado(doc, 4, 6)
    borrados = Enum.with_index(posiciones, 11) |> Enum.map(fn {pos, seq} -> %{op: :del, from: :autor, vc: %{autor: seq}, pos: pos} end)
    assert Treedoc.texto(Treedoc.aplicar_todos(doc, borrados)) == "Hola"
  end

  test "operaciones concurrentes convergen sin depender del orden de entrega" do
    {_, ops_a} = insertar(Treedoc.nuevo(), "X", 0, :a)
    {_, ops_b} = insertar(Treedoc.nuevo(), "Y", 0, :b)
    primero = Treedoc.aplicar_todos(Treedoc.nuevo(), ops_a ++ ops_b)
    segundo = Treedoc.aplicar_todos(Treedoc.nuevo(), ops_b ++ ops_a)
    assert Treedoc.texto(primero) == Treedoc.texto(segundo)
    assert Treedoc.texto(primero) == "XY"
  end

  test "un borrado recibido antes de su inserción deja el carácter oculto" do
    {_, [insertar_op]} = insertar(Treedoc.nuevo(), "Z", 0, :a)
    pos = insertar_op.pos
    borrar_op = %{op: :del, from: :b, vc: %{b: 1}, pos: pos}
    doc = Treedoc.aplicar_todos(Treedoc.nuevo(), [borrar_op, insertar_op])
    assert Treedoc.texto(doc) == ""
  end

  test "un pegado largo produce identificadores por carácter y conserva el texto" do
    texto = String.duplicate("abc", 500)
    {doc, operaciones} = insertar(Treedoc.nuevo(), texto)
    assert length(operaciones) == String.length(texto)
    assert Treedoc.texto(doc) == texto
  end
end
