defmodule HermesBeam.LLM.TierSupervisor do
  @moduledoc """
  Dynamically supervises one `ModelWorker` per LLM tier assigned to this
  node's hardware.

  Which tiers are loaded is determined entirely by `NODE_ROLE` at startup
  (see `config/runtime.exs`). A Gaming PC will supervise up to two workers
  (Tier 1 + Tier 2); a base Mac Mini will supervise only Tier 3.
  """
  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    topology     = Application.fetch_env!(:hermes_beam, :topology)
    active_tiers = Keyword.fetch!(topology, :active_tiers)

    Logger.info("[TierSupervisor] Loading #{length(active_tiers)} model tier(s): #{inspect(Keyword.keys(active_tiers))}")

    children =
      Enum.map(active_tiers, fn {tier_name, hf_repo} ->
        Supervisor.child_spec(
          {HermesBeam.LLM.ModelWorker, {tier_name, hf_repo}},
          id: tier_name
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
