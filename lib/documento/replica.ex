defmodule Documento.Replica do
  use GenServer
  require Logger

  alias Documento.{Almacenamiento, Causal, Difusion, Mensaje, Treedoc}

  @nombre Crdt.Replica
  @espera 30_000
  @anti_entropia 30_000

  def nombre, do: @nombre

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: @nombre)
  def insertar(indice, texto), do: GenServer.call(@nombre, {:insertar, indice, texto}, @espera)
  def borrar(indice, cantidad \\ 1), do: GenServer.call(@nombre, {:borrar, indice, cantidad}, @espera)
  def texto, do: GenServer.call(@nombre, :texto, @espera)
  def estado, do: GenServer.call(@nombre, :estado, @espera)
  def historial, do: GenServer.call(@nombre, :historial, @espera)
  def depurar, do: GenServer.call(@nombre, :depurar, @espera)
  def suscribir(pid \\ self()), do: GenServer.call(@nombre, {:suscribir, pid}, @espera)
  def sincronizar, do: GenServer.cast(@nombre, :sincronizar)

  @impl true
  def init(:ok) do
    activar_monitoreo()
    Process.send_after(self(), :anti_entropia, @anti_entropia)
    {doc, vector, operaciones} = recuperar()

    archivo =
      case Almacenamiento.abrir() do
        {:ok, fd} -> fd
        :error -> nil
      end

    estado = %{
      doc: doc,
      vc: vector,
      espera: [],
      historial: operaciones,
      n_historial: length(operaciones),
      archivo: archivo,
      suscritos: [],
      texto_avisado: nil,
      recibidas: 0,
      duplicadas: 0,
      ignoradas: 0,
      reenviadas: 0
    }

    if Node.list() != [] do
      enviar_historial(estado)
      Difusion.difundir({:hello, node()})
    end

    {:ok, estado}
  end

  @impl true
  def handle_call({:insertar, indice, texto}, _de, estado) when is_binary(texto) do
    if String.valid?(texto) do
      caracteres = String.graphemes(texto)

      if caracteres == [] do
        {:reply, {:error, :texto_vacio}, estado}
      else
        autor = node()
        secuencia = Map.get(estado.vc, autor, 0)

        case Treedoc.preparar_insercion(estado.doc, indice, caracteres, secuencia, autor) do
          {:ok, ubicaciones} ->
            operaciones =
              Enum.map(ubicaciones, fn {pos, ch} ->
                seq = pos |> List.last() |> elem(1)
                %{op: :ins, from: autor, vc: Map.put(estado.vc, autor, seq), pos: pos, ch: ch}
              end)

            guardar_local(operaciones, estado)

          {:error, razon} -> {:reply, {:error, razon}, estado}
        end
      end
    else
      {:reply, {:error, :texto_invalido}, estado}
    end
  end

  def handle_call({:insertar, _indice, _texto}, _de, estado), do: {:reply, {:error, :texto_invalido}, estado}

  def handle_call({:borrar, indice, cantidad}, _de, estado) do
    case Treedoc.preparar_borrado(estado.doc, indice, cantidad) do
      {:ok, []} -> {:reply, :ok, estado}
      {:ok, posiciones} ->
        autor = node()
        base = Map.get(estado.vc, autor, 0)
        operaciones =
          posiciones
          |> Enum.with_index(base + 1)
          |> Enum.map(fn {pos, seq} -> %{op: :del, from: autor, vc: Map.put(estado.vc, autor, seq), pos: pos} end)

        guardar_local(operaciones, estado)

      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  def handle_call(:texto, _de, estado), do: {:reply, Treedoc.texto(estado.doc), estado}
  def handle_call(:historial, _de, estado), do: {:reply, Enum.reverse(estado.historial), estado}
  def handle_call(:depurar, _de, estado), do: {:reply, %{orden: Treedoc.orden(estado.doc), borrados: estado.doc.borrados}, estado}

  def handle_call(:estado, _de, estado) do
    resumen = %{
      nodo: node(), nodos: Node.list(), reloj: estado.vc,
      en_espera: Enum.map(estado.espera, fn op -> {op.from, Map.get(op.vc, op.from), Causal.faltan(estado.vc, op)} end),
      historial: estado.n_historial, caracteres: map_size(estado.doc.atomos),
      borrados: MapSet.size(estado.doc.borrados), recibidas: estado.recibidas,
      duplicadas: estado.duplicadas, ignoradas: estado.ignoradas,
      persistente: estado.archivo != nil
    }
    {:reply, resumen, estado}
  end

  def handle_call({:suscribir, pid}, _de, estado) when is_pid(pid) do
    Process.monitor(pid)
    {:reply, :ok, %{estado | suscritos: Enum.uniq([pid | estado.suscritos])}}
  end

  def handle_call(_otro, _de, estado), do: {:reply, {:error, :desconocida}, estado}

  @impl true
  def handle_cast({:remote, crudo}, estado), do: {:noreply, recibir(crudo, estado)}
  def handle_cast({:hello, _nodo}, estado), do: {:noreply, enviar_historial(estado)}
  def handle_cast(:sincronizar, estado), do: {:noreply, enviar_historial(estado)}
  def handle_cast(_otro, estado), do: {:noreply, %{estado | ignoradas: estado.ignoradas + 1}}

  @impl true
  def handle_info({:remote, crudo}, estado), do: {:noreply, recibir(crudo, estado)}
  def handle_info({:nodeup, _nodo}, estado) do
    estado = enviar_historial(estado)
    Difusion.difundir({:hello, node()})
    {:noreply, estado}
  end
  def handle_info(:distribucion_lista, estado) do
    activar_monitoreo()
    estado = enviar_historial(estado)
    Difusion.difundir({:hello, node()})
    {:noreply, estado}
  end
  def handle_info(:anti_entropia, estado) do
    Process.send_after(self(), :anti_entropia, @anti_entropia)
    {:noreply, enviar_historial(estado)}
  end
  def handle_info({:DOWN, _ref, :process, pid, _razon}, estado) do
    {:noreply, %{estado | suscritos: List.delete(estado.suscritos, pid)}}
  end
  def handle_info(_otro, estado), do: {:noreply, %{estado | ignoradas: estado.ignoradas + 1}}

  defp guardar_local([], estado), do: {:reply, :ok, estado}
  defp guardar_local(operaciones, %{archivo: nil} = estado), do: {:reply, {:error, :sin_almacenamiento}, estado}
  defp guardar_local(operaciones, estado) do
    if Enum.all?(operaciones, &(Mensaje.leer(&1) != :error)) do
      case Almacenamiento.guardar_varios(estado.archivo, operaciones) do
        :ok ->
          estado = aplicar_operaciones(operaciones, estado)
          Enum.each(operaciones, &Difusion.difundir({:remote, &1}))
          {:reply, :ok, avisar(estado)}
        {:error, razon} -> {:reply, {:error, {:disco, razon}}, estado}
      end
    else
      {:reply, {:error, :operacion_invalida}, estado}
    end
  end

  defp recibir(crudo, estado) do
    case Mensaje.leer(crudo) do
      {:ok, operacion} ->
        {vector, espera, aplicadas, resultado} = Causal.recibir(estado.vc, estado.espera, operacion)
        estado = %{estado | vc: vector, espera: espera}

        cond do
          resultado == :duplicada -> %{estado | duplicadas: estado.duplicadas + 1}
          aplicadas == [] -> estado
          true ->
            if estado.archivo != nil, do: Almacenamiento.guardar_varios(estado.archivo, aplicadas)
            estado = aplicar_operaciones(aplicadas, estado)
            Enum.each(aplicadas, &Difusion.difundir({:remote, &1}))
            avisar(%{estado | recibidas: estado.recibidas + length(aplicadas), reenviadas: estado.reenviadas + length(aplicadas)})
        end

      :error -> %{estado | ignoradas: estado.ignoradas + 1}
    end
  end

  defp aplicar_operaciones(operaciones, estado) do
    doc = Treedoc.aplicar_todos(estado.doc, operaciones)
    vector = Enum.reduce(operaciones, estado.vc, &Causal.entregar(&2, &1))
    %{estado | doc: doc, vc: vector, historial: Enum.reverse(operaciones, estado.historial), n_historial: estado.n_historial + length(operaciones)}
  end

  defp enviar_historial(estado) do
    Enum.each(Enum.reverse(estado.historial), &Difusion.difundir({:remote, &1}))
    estado
  end

  defp avisar(estado) do
    texto = Treedoc.texto(estado.doc)
    if texto == estado.texto_avisado do
      estado
    else
      Enum.each(estado.suscritos, &send(&1, {:documento, texto}))
      %{estado | texto_avisado: texto}
    end
  end

  defp recuperar do
    Enum.reduce(Almacenamiento.cargar(), {Treedoc.nuevo(), %{}, []}, fn registro, {doc, vector, ops} ->
      case Mensaje.leer(registro) do
        {:ok, operacion} ->
          case Causal.recibir(vector, [], operacion) do
            {nuevo_vector, [], [aplicada], _} -> {Treedoc.aplicar(doc, aplicada), nuevo_vector, [aplicada | ops]}
            _ -> {doc, vector, ops}
          end
        :error -> {doc, vector, ops}
      end
    end)
  end

  defp activar_monitoreo do
    if Node.alive?(), do: :net_kernel.monitor_nodes(true)
    :ok
  end
end
