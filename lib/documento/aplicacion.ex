defmodule Documento.Aplicacion do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    hijos = hijos_target() ++ [Documento.Replica, Documento.Descubrimiento]
    opciones = [strategy: :one_for_one, name: Documento.Supervisor]
    Supervisor.start_link(hijos, opciones)
  end

  if Mix.target() == :host do
    defp hijos_target() do
      []
    end
  else
    defp hijos_target() do
      [Documento.Red]
    end
  end
end
