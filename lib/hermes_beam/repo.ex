defmodule HermesBeam.Repo do
  @moduledoc """
  The Ecto/AshPostgres repository for Hermes BEAM.

  All persistent agent state — memories, scratchpads, skills, workflow logs —
  is stored here. On Hub nodes this connects to localhost; on Worker nodes it
  connects to the Hub's Tailscale IP.
  """
  use AshPostgres.Repo, otp_app: :hermes_beam

  def installed_extensions do
    # pgvector is required for semantic memory similarity search.
    ["uuid-ossp", "citext", "vector", AshPostgres.Extensions.Vector]
  end
end
