defmodule Documento.CausalTest do
  use ExUnit.Case, async: true
  alias Documento.Causal

  test "espera una dependencia y entrega en orden causal al llegar" do
    a = :a
    b = :b
    op1 = %{op: :ins, from: a, vc: %{a => 1}, pos: [{1, 1, a}], ch: "a"}
    op2 = %{op: :ins, from: b, vc: %{a => 1, b => 1}, pos: [{1, 1, b}], ch: "b"}

    {vc, espera, aplicadas, :espera} = Causal.recibir(%{}, [], op2)
    assert vc == %{}
    assert espera == [op2]
    {vc, espera, aplicadas, :aplicada} = Causal.recibir(vc, espera, op1)
    assert espera == []
    assert Enum.map(aplicadas, & &1.from) == [a, b]
    assert vc == %{a => 1, b => 1}
  end

  test "ignora una operación ya entregada" do
    op = %{op: :ins, from: :a, vc: %{a: 1}, pos: [{1, 1, :a}], ch: "x"}
    assert { %{a: 1}, [], [], :duplicada } = Causal.recibir(%{a: 1}, [], op)
  end
end
