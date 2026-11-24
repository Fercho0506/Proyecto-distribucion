defmodule Documento do
  alias Documento.{Descubrimiento, Replica}

  def insertar(indice, texto) do
    Replica.insertar(indice, texto)
  end

  def borrar(indice, cantidad \\ 1) do
    Replica.borrar(indice, cantidad)
  end

  def texto() do
    Replica.texto()
  end

  def estado() do
    Replica.estado()
  end

  def historial() do
    Replica.historial()
  end

  def depurar() do
    Replica.depurar()
  end

  def sincronizar() do
    Replica.sincronizar()
  end

  def nodos() do
    Node.list()
  end

  def conectar(ip) do
    Descubrimiento.conectar(ip)
  end

  def ver() do
    pid = spawn(fn -> mostrar() end)
    Replica.suscribir(pid)
    IO.puts("[documento] " <> Replica.texto())
    pid
  end

  def dejar_de_ver(pid) do
    Process.exit(pid, :kill)
    :ok
  end

  defp mostrar() do
    receive do
      {:documento, texto} ->
        IO.puts("[documento] " <> texto)
        mostrar()
    end
  end
end
