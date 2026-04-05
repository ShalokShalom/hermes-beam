defmodule HermesBeam.Domain do
  @moduledoc """
  The central Ash Domain for Hermes BEAM.

  All Ash Resources in the application are registered here. Ash uses this
  domain to resolve relationships, run policy checks, and co-ordinate actions
  across resources.
  """
  use Ash.Domain,
    extensions: [AshAi.Domain]

  resources do
    # Memory
    resource HermesBeam.Memory.Scratchpad
    resource HermesBeam.Memory.Episodic

    # Skills
    resource HermesBeam.Skill

    # Observability
    resource HermesBeam.WorkflowLog
  end
end
