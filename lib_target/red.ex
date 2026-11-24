defmodule Documento.Red do
  use GenServer

  require Logger

  @cookie :cpd2026

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    VintageNet.subscribe(["interface", "wlan0", "addresses"])
    send(self(), :revisar)
    {:ok, %{ip: nil}}
  end

  @impl true
  def handle_info(:revisar, estado) do
    direcciones = VintageNet.get(["interface", "wlan0", "addresses"], [])
    {:noreply, actualizar(ipv4(direcciones), estado)}
  end

  def handle_info({VintageNet, _propiedad, _viejo, nuevo, _meta}, estado) do
    {:noreply, actualizar(ipv4(nuevo), estado)}
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp actualizar(ip, estado) do
    if ip == estado.ip and Node.alive?() do
      estado
    else
      detener_nodo()
      arrancar_nodo(ip)
    end
  end

  defp detener_nodo() do
    if Node.alive?() do
      Logger.info("[documento] deteniendo el nodo #{inspect(Node.self())}")
      Node.stop()
    end
  end

  defp arrancar_nodo(nil) do
    Logger.info("[documento] wlan0 sin IPv4, esperando")
    %{ip: nil}
  end

  defp arrancar_nodo(ip) do
    iniciar_epmd()
    nombre = String.to_atom("#{host()}-#{epoca()}@#{ip}")

    case :net_kernel.start(nombre, %{name_domain: :longnames}) do
      {:ok, _pid} ->
        Node.set_cookie(@cookie)
        Logger.info("[documento] nodo arrancado: #{inspect(Node.self())}")
        if Process.whereis(Crdt.Replica), do: send(Crdt.Replica, :distribucion_lista)
        if Process.whereis(Documento.Descubrimiento), do: send(Documento.Descubrimiento, :buscar)
        %{ip: ip}

      {:error, razon} ->
        Logger.warning("[documento] no se pudo arrancar #{inspect(nombre)}: #{inspect(razon)}, reintento en 5 s")
        Process.send_after(self(), :revisar, 5_000)
        %{ip: nil}
    end
  end


  defp host() do
    {:ok, nombre} = :inet.gethostname()
    nombre |> to_string() |> String.replace(~r/[^A-Za-z0-9_-]/, "-")
  end

  defp epoca() do
    Application.ensure_all_started(:crypto)
    archivo = Application.fetch_env!(:documento, :epoca)

    case File.read(archivo) do
      {:ok, valor} when byte_size(valor) == 6 ->
        if Regex.match?(~r/\A[0-9a-f]{6}\z/, valor), do: valor, else: nueva_epoca(archivo)
      _ -> nueva_epoca(archivo)
    end
  end

  defp nueva_epoca(archivo) do
    valor = Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
    File.mkdir_p(Path.dirname(archivo))
    case File.write(archivo, valor, [:sync]) do
      :ok -> valor
      {:error, razon} ->
        Logger.warning("[documento] no se pudo persistir la época: #{inspect(razon)}")
        valor
    end
  end

  # epmd tiene que estar corriendo antes de arrancar la distribución a mano.
  defp iniciar_epmd() do
    epmd = System.find_executable("epmd") || epmd_en_erts()

    if epmd != nil do
      System.cmd(epmd, ["-daemon"])
    end

    :ok
  end

  defp epmd_en_erts() do
    List.first(Path.wildcard(Path.join([:code.root_dir(), "erts-*", "bin", "epmd"])))
  end

  defp ipv4(nil) do
    nil
  end

  defp ipv4(direcciones) do
    case Enum.find(direcciones, fn d -> d.family == :inet end) do
      nil -> nil
      d -> Enum.join(Tuple.to_list(d.address), ".")
    end
  end
end
