defmodule Documento.MensajeTest do
  use ExUnit.Case, async: true
  alias Documento.Mensaje

  test "acepta operaciones de inserción y borrado del protocolo compartido" do
    autor = :"equipo@192.168.1.10"
    pos = [{1, 1, autor}]
    ins = %{op: :ins, from: autor, vc: %{autor => 1}, pos: pos, ch: "ñ"}
    del = %{op: :del, from: autor, vc: %{autor => 2}, pos: pos}
    assert Mensaje.leer(ins) == {:ok, ins}
    assert Mensaje.leer(del) == {:ok, del}
    assert Mensaje.nombre() == Crdt.Replica
  end

  test "rechaza operaciones mal formadas" do
    autor = :"equipo@192.168.1.10"
    base = %{op: :ins, from: autor, vc: %{autor => 1}, pos: [{1, 1, autor}], ch: "x"}
    assert Mensaje.leer(%{base | ch: "xy"}) == :error
    assert Mensaje.leer(%{base | vc: %{autor => 0}}) == :error
    assert Mensaje.leer(%{base | pos: [{2, 1, autor}]}) == :error
    assert Mensaje.leer(%{base | pos: []}) == :error
    assert Mensaje.leer(:basura) == :error
  end
end
