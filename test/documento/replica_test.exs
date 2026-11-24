defmodule Documento.ReplicaTest do
  use ExUnit.Case, async: false
  alias Documento.{Difusion, Replica}

  test "broadcast no envía nada si no hay nodos conectados" do
    assert Difusion.difundir({:remote, :basura}) == {0, 0}
  end

  test "la réplica edita, recibe operaciones, deduplica y persiste" do
    pid = Process.whereis(Crdt.Replica)
    assert is_pid(pid)

    assert Replica.insertar(0, "Hola") == :ok
    assert Replica.texto() == "Hola"
    assert Replica.insertar(99, "x") == {:error, :posicion_invalida}
    assert Replica.insertar(0, "") == {:error, :texto_vacio}
    assert Replica.borrar(0, 1) == :ok
    assert Replica.texto() == "ola"

    autor = :"otro@192.168.1.20"
    operacion = %{op: :ins, from: autor, vc: %{autor => 1}, pos: [{0, 1, autor}], ch: "!"}
    GenServer.cast(Crdt.Replica, {:remote, operacion})
    assert_eventually(fn -> String.contains?(Replica.texto(), "!") end)

    antes = Replica.estado()
    GenServer.cast(Crdt.Replica, {:remote, operacion})
    GenServer.cast(Crdt.Replica, {:remote, %{operacion | ch: "ab"}})
    assert_eventually(fn -> Replica.estado().duplicadas > antes.duplicadas end)
    assert Replica.estado().ignoradas > antes.ignoradas
    assert Process.whereis(Crdt.Replica) == pid

    historial = Replica.historial()
    assert Enum.any?(historial, &(&1.op == :ins))
    assert Replica.estado().persistente

    texto_final = Replica.texto()
    :ok = Supervisor.terminate_child(Documento.Supervisor, Documento.Replica)
    {:ok, _} = Supervisor.restart_child(Documento.Supervisor, Documento.Replica)
    assert Replica.texto() == texto_final
  end

  defp assert_eventually(fun, intentos \\ 50)
  defp assert_eventually(fun, 0), do: assert(fun.())
  defp assert_eventually(fun, intentos) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(fun, intentos - 1)
    end
  end
end
