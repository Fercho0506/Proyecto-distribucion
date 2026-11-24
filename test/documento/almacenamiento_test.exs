defmodule Documento.AlmacenamientoTest do
  use ExUnit.Case, async: false

  alias Documento.Almacenamiento

  setup do
    anterior = Application.get_env(:documento, :directorio_datos)

    directorio =
      Path.join(System.tmp_dir!(), "documento_almacenamiento_#{System.unique_integer([:positive])}")

    Application.put_env(:documento, :directorio_datos, directorio)

    on_exit(fn ->
      Application.put_env(:documento, :directorio_datos, anterior)
      File.rm_rf(directorio)
    end)

    :ok
  end

  test "sin registro no hay nada que cargar" do
    assert Almacenamiento.cargar() == []
  end

  test "lo que se guarda se carga igual y en orden" do
    {:ok, archivo} = Almacenamiento.abrir()

    assert Almacenamiento.guardar(archivo, {:cpd, 1, :a, {:estado, [], []}}) == :ok
    assert Almacenamiento.guardar(archivo, {:otro, "ñ"}) == :ok
    :file.close(archivo)

    assert Almacenamiento.cargar() == [{:cpd, 1, :a, {:estado, [], []}}, {:otro, "ñ"}]
  end

  test "una línea cortada por un apagón se pierde sola y no daña la siguiente" do
    {:ok, archivo} = Almacenamiento.abrir()
    :ok = Almacenamiento.guardar(archivo, {:uno, 1})
    :file.write(archivo, "AAAA")
    :file.close(archivo)

    {:ok, archivo} = Almacenamiento.abrir()
    :ok = Almacenamiento.guardar(archivo, {:dos, 2})
    :file.close(archivo)

    assert Almacenamiento.cargar() == [{:uno, 1}, {:dos, 2}]
  end

  test "sin archivo abierto guardar falla sin tumbar a nadie" do
    assert Almacenamiento.guardar(nil, {:uno, 1}) == :error
  end
end
