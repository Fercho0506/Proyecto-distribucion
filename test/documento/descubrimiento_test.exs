defmodule Documento.DescubrimientoTest do
  use ExUnit.Case, async: true

  alias Documento.Descubrimiento

  test "vecinos en la subred /28 del hotspot de iPhone" do
    vecinos = Descubrimiento.vecinos("172.20.10.3", 28)

    assert length(vecinos) == 13
    assert hd(vecinos) == "172.20.10.1"
    assert List.last(vecinos) == "172.20.10.14"
    refute "172.20.10.3" in vecinos
  end

  test "vecinos en una /24 y en una /28 que no empieza en 0" do
    assert length(Descubrimiento.vecinos("192.168.43.10", 24)) == 253

    assert Descubrimiento.vecinos("10.0.0.20", 28) ==
             Enum.map(17..30, fn x -> "10.0.0.#{x}" end) -- ["10.0.0.20"]
  end

  test "en una /30 solo quedan las dos direcciones útiles" do
    assert Descubrimiento.vecinos("10.0.0.5", 30) == ["10.0.0.6"]
  end

  test "subredes más grandes que /24 o sin vecinos no se recorren" do
    assert Descubrimiento.vecinos("10.1.2.3", 16) == []
    assert Descubrimiento.vecinos("10.1.2.3", 31) == []
    assert Descubrimiento.vecinos("10.1.2.3", 32) == []
    assert Descubrimiento.vecinos("10.1.2.3", nil) == []
  end

  test "la IP sale del nombre del nodo" do
    assert Descubrimiento.ip_de_nodo(:"doc@172.20.10.4") == "172.20.10.4"
    assert Descubrimiento.ip_de_nodo(:nonode) == nil
    assert Descubrimiento.nombre_de_nodo("172.20.10.4") == :"doc@172.20.10.4"
  end

  test "una IP que no está en ninguna interfaz no tiene prefijo" do
    assert Descubrimiento.prefijo_de("203.0.113.77") == nil
  end
end
