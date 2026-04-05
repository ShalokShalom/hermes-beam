defmodule HermesBeam.Application do
  @moduledoc """
  The OTP Application entry point for Hermes BEAM.

  The supervision tree is shaped by two environment variables:

  - `NODE_TYPE` ("hub" | "worker") — determines whether the Phoenix dashboard
    and cluster coordinator processes are started.
  - `NODE_ROLE` ("gaming_gpu" | "mac_mini_pro" | "mac_mini_base") — determines
    which Bumblebee models are loaded into VRAM / Unified Memory.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    topology  = Application.fetch_env!(:hermes_beam, :topology)
    node_type = Keyword.fetch!(topology, :type)
    node_role = Keyword.fetch!(topology, :role)

    Logger.info("[HermesBeam] Booting as #{node_type} / #{node_role}")

    children =
      base_children() ++
        cluster_children() ++
        ml_children() ++
        dashboard_children(node_type)

    opts = [strategy: :one_for_one, name: HermesBeam.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ---------------------------------------------------------------------------
  # Child groups
  # ---------------------------------------------------------------------------

  # Every node — Hub and Workers alike — starts the Repo, PubSub, and Ash.
  defp base_children do
    [
      HermesBeam.Repo,
      {Phoenix.PubSub, name: HermesBeam.PubSub},
      {Ash, domain: HermesBeam.Domain}
    ]
  end

  # Cluster discovery via libcluster_postgres.
  defp cluster_children do
    topologies = Application.get_env(:hermes_beam, :libcluster)[:topologies]

    [
      {Cluster.Supervisor, [topologies, [name: HermesBeam.ClusterSupervisor]]}
    ]
  end

  # Model serving — only loads the tiers appropriate for this machine's hardware.
  defp ml_children do
    [HermesBeam.LLM.TierSupervisor]
  end

  # Phoenix LiveView dashboard — Hub nodes only.
  defp dashboard_children("hub") do
    Logger.info("[HermesBeam] Hub mode: starting Phoenix LiveView dashboard")

    [
      HermesBeamWeb.Telemetry,
      HermesBeamWeb.Endpoint
    ]
  end

  defp dashboard_children(_worker), do: []

  @impl true
  def config_change(changed, _new, removed) do
    HermesBeamWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
