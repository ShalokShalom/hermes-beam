# Hermes BEAM — classic nix-shell dev environment
#
# Usage:
#   nix-shell          # enters the dev shell
#   nix-shell --run 'mix test'   # runs tests without entering interactively
#
# For flake-based usage see nix/devshell.nix and run:
#   nix develop ./nix#devshell

{ pkgs ? import <nixpkgs> {} }:

let
  # Pin Erlang/OTP to 26 to match .tool-versions.
  # erlang and elixir in nixpkgs are versioned as separate attributes.
  beam = pkgs.beam.packages.erlang_26;
  elixir = beam.elixir_1_16;
  erlang = beam.erlang;

in pkgs.mkShell {
  name = "hermes-beam";

  buildInputs = [
    # --- Erlang / Elixir ---
    erlang
    elixir

    # --- Build tools ---
    pkgs.git
    pkgs.gnumake
    pkgs.gcc

    # --- Node.js (for esbuild / Tailwind asset pipeline) ---
    pkgs.nodejs_20

    # --- PostgreSQL 15 + pgvector ---
    pkgs.postgresql_15
    pkgs.pgvector          # provides the pgvector.so extension

    # --- Useful CLI tools for development ---
    pkgs.curl
    pkgs.jq
    pkgs.inotify-tools     # for Phoenix live reload on Linux
  ];

  # Keep Elixir build artefacts out of the global store.
  # $MIX_HOME and $HEX_HOME are local to the project so multiple clones
  # do not share state and `nix-shell --pure` works correctly.
  shellHook = ''
    export MIX_HOME=$PWD/.nix-mix
    export HEX_HOME=$PWD/.nix-hex
    export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
    export PGDATA=$PWD/.nix-pgdata
    export PGHOST=127.0.0.1
    export PGPORT=5432

    # -----------------------------------------------------------------------
    # One-time Postgres initialisation inside the project directory.
    # Creates a local cluster at .nix-pgdata so no system Postgres is needed.
    # -----------------------------------------------------------------------
    if [ ! -d "$PGDATA" ]; then
      echo "[nix-shell] Initialising local Postgres cluster at $PGDATA..."
      initdb --username=postgres --auth=trust --no-locale --encoding=UTF8 "$PGDATA"

      # Allow local connections without a password from any role.
      echo "host all all 127.0.0.1/32 trust" >> "$PGDATA/pg_hba.conf"
      echo "host all all ::1/128        trust" >> "$PGDATA/pg_hba.conf"
    fi

    # Start Postgres if it is not already running.
    if ! pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
      echo "[nix-shell] Starting local Postgres..."
      pg_ctl -D "$PGDATA" -l "$PGDATA/postgres.log" start

      # Give the server a moment to accept connections before we continue.
      sleep 1

      # Install pgvector into the cluster (only needed once).
      psql -U postgres -d postgres -c \
        "CREATE EXTENSION IF NOT EXISTS vector;" > /dev/null 2>&1 || true
    fi

    # -----------------------------------------------------------------------
    # Elixir bootstrapping — installs hex and rebar if not already present.
    # -----------------------------------------------------------------------
    mix local.hex  --if-missing --force > /dev/null
    mix local.rebar --if-missing --force > /dev/null

    echo ""
    echo "  Hermes BEAM dev shell ready"
    echo "  Erlang/OTP : $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || echo unknown)"
    echo "  Elixir     : $(elixir --version | head -1)"
    echo "  Postgres   : $(psql --version)"
    echo ""
    echo "  Quick start:"
    echo "    mix deps.get && mix ecto.setup && mix test"
    echo ""
  '';
}
