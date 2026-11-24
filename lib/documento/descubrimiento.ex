defmodule Documento.Descubrimiento do
  use GenServer

  alias Documento.Replica

  @intervalo 10_000
  @nombre_valido ~r/\A[A-Za-z0-9_\-.]{1,64}@\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def conectar(destino) when is_atom(destino) do
    Node.connect(destino)
  end

  def conectar(destino) when is_binary(destino) do
    case String.split(destino, "@") do
      [_ip] ->
        ip = destino
        candidatos = Enum.uniq([nombre_de_nodo(ip) | nodos_en(ip)])
        Enum.reduce_while(candidatos, false, fn nodo, conectado ->
          if conectado or nodo == node() do
            {:halt, conectado}
          else
            case Node.connect(nodo) do
              true -> {:halt, true}
              _ -> {:cont, false}
            end
          end
        end)

      [_nombre, _ip] -> Node.connect(String.to_atom(destino))
      _ -> {:error, :nodo_invalido}
    end
  end

  def conectar(_), do: {:error, :nodo_invalido}

  def nombre_de_nodo(ip) do
    String.to_atom("doc@" <> ip)
  end

  def ip_de_nodo(nodo) do
    case String.split(Atom.to_string(nodo), "@") do
      [_nombre, ip] -> ip
      _otro -> nil
    end
  end

  def vecinos(ip, prefijo) do
    if is_integer(prefijo) and prefijo >= 24 and prefijo <= 30 do
      [a, b, c, d] = Enum.map(String.split(ip, "."), fn x -> String.to_integer(x) end)
      tamano = Integer.pow(2, 32 - prefijo)
      base = d - rem(d, tamano)

      for x <- (base + 1)..(base + tamano - 2), x != d do
        Enum.join([a, b, c, x], ".")
      end
    else
      []
    end
  end

  def prefijo_de(ip) do
    case :inet.getifaddrs() do
      {:ok, interfaces} -> buscar_prefijo(interfaces, ip)
      _otro -> nil
    end
  end

  @impl true
  def init(:ok) do
    Process.send_after(self(), :buscar, 1_000)
    {:ok, %{conocidos: []}}
  end

  @impl true
  def handle_info(:buscar, estado) do
    buscar()
    estado = revisar_nuevos(estado)
    Process.send_after(self(), :buscar, @intervalo)
    {:noreply, estado}
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp buscar() do
    if Node.alive?() do
      :net_kernel.monitor_nodes(true)
      ip = ip_de_nodo(node())

      cercanos =
        if ip == nil do
          []
        else
          vecinos(ip, prefijo_de(ip) || 24)
        end

      explicitos = Application.get_env(:documento, :nodos, [])
      destinos = Enum.uniq(cercanos ++ explicitos) -- [ip]

      destinos
      |> Task.async_stream(&conectar_aparte/1, max_concurrency: 64, timeout: 5_000, on_timeout: :kill_task)
      |> Stream.run()
    end

    :ok
  end

  defp conectar_aparte(destino) do
    candidatos = Enum.uniq([nombre_de_nodo(destino) | nodos_en(destino)])
    Enum.each(candidatos, fn nodo ->
      if nodo != node() and nodo not in Node.list(), do: Node.connect(nodo)
    end)
    :ok
  end

  defp nodos_en(ip) do
    with {:ok, direccion} <- :inet.parse_ipv4_address(String.to_charlist(ip)) do
      tarea = Task.async(fn -> :erl_epmd.names(direccion) end)

      case Task.yield(tarea, 2_500) do
        {:ok, {:ok, nombres}} ->
          for {nombre, _puerto} <- nombres,
              Regex.match?(@nombre_valido, "#{nombre}@#{ip}") do
            String.to_atom("#{nombre}@#{ip}")
          end

        nil ->
          Task.shutdown(tarea, :brutal_kill)
          []

        _ -> []
      end
    else
      _ -> []
    end
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  defp revisar_nuevos(estado) do
    actuales = Node.list()

    if actuales -- estado.conocidos != [] do
      Replica.sincronizar()
    end

    %{estado | conocidos: actuales}
  end

  defp buscar_prefijo([], _ip) do
    nil
  end

  defp buscar_prefijo([{_nombre, opciones} | resto], ip) do
    case prefijo_en(opciones, ip) do
      nil -> buscar_prefijo(resto, ip)
      prefijo -> prefijo
    end
  end

  defp prefijo_en([{:addr, direccion}, {:netmask, mascara} | resto], ip) do
    if tuple_size(direccion) == 4 and Enum.join(Tuple.to_list(direccion), ".") == ip do
      contar_bits(mascara)
    else
      prefijo_en(resto, ip)
    end
  end

  defp prefijo_en([_otra | resto], ip) do
    prefijo_en(resto, ip)
  end

  defp prefijo_en([], _ip) do
    nil
  end

  defp contar_bits(mascara) do
    Enum.reduce(Tuple.to_list(mascara), 0, fn byte, acumulado ->
      acumulado + bits_en(byte, 0)
    end)
  end

  defp bits_en(0, acumulado) do
    acumulado
  end

  defp bits_en(n, acumulado) do
    bits_en(div(n, 2), acumulado + rem(n, 2))
  end
end
