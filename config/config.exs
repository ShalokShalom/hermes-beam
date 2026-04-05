import Config

# ---------------------------------------------------------------------------
# Nx / EXLA — use EXLA as the default tensor backend globally.
# EXLA will automatically compile to CUDA on NVIDIA hardware and Metal on
# Apple Silicon at runtime, based on what is available.
# ---------------------------------------------------------------------------
config :nx, default_backend: EXLA.Backend

config :exla, :clients,
  cuda: [platform: :cuda],
  rocm: [platform: :rocm],
  tpu: [platform: :tpu],
  host: [platform: :host]

# ---------------------------------------------------------------------------
# Ash Framework
# ---------------------------------------------------------------------------
config :ash,
  default_belongs_to_type: :uuid,
  custom_types: [vector: Ash.Type.Vector]

# ---------------------------------------------------------------------------
# Ash Postgres
# ---------------------------------------------------------------------------
config :hermes_beam, ecto_repos: [HermesBeam.Repo]

# ---------------------------------------------------------------------------
# Libcluster — using Postgres strategy so the DB serves as the cluster
# registry. Workers find the Hub by connecting to the same Postgres instance
# over the Tailscale VPN. Channel and credentials are overridden at runtime.
# ---------------------------------------------------------------------------
config :hermes_beam, :libcluster,
  topologies: [
    postgres_mesh: [
      strategy: Cluster.Strategy.Postgres,
      config: [
        channel_name: "hermes_beam_cluster"
      ]
    ]
  ]

# ---------------------------------------------------------------------------
# Phoenix Endpoint (base — overridden per environment below)
# ---------------------------------------------------------------------------
config :hermes_beam, HermesBeamWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HermesBeamWeb.ErrorHTML, json: HermesBeamWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HermesBeam.PubSub,
  live_view: [signing_salt: "hermes_lv_salt"]

# ---------------------------------------------------------------------------
# Esbuild
# ---------------------------------------------------------------------------
config :esbuild,
  version: "0.17.11",
  hermes_beam: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets
         --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# ---------------------------------------------------------------------------
# Tailwind CSS
# ---------------------------------------------------------------------------
config :tailwind,
  version: "3.4.3",
  hermes_beam: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# ---------------------------------------------------------------------------
# Logger
# ---------------------------------------------------------------------------
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :node]

import_config "#{config_env()}.exs"
