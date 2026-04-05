import Config

config :hermes_beam, HermesBeam.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "hermes_beam_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :hermes_beam, HermesBeamWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_at_least_64_chars_long_replace_in_prod_00000000",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:hermes_beam, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:hermes_beam, ~w(--watch)]}
  ]

config :hermes_beam, HermesBeamWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/hermes_beam_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :logger, level: :debug
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, :debug_heex_annotations, true
