# Hermes BEAM — flake-compatible dev shell
#
# Consumed by a top-level flake.nix or used standalone:
#   nix develop ./nix#devshell
#
# This file is intentionally self-contained so it can be imported by a
# parent flake without requiring a full project-level flake.nix.
# The shell is functionally identical to shell.nix.

{ pkgs }:

let
  beam    = pkgs.beam.packages.erlang_26;
  elixir  = beam.elixir_1_16;
  erlang  = beam.erlang;
in

pkgs.mkShell {
  name = "hermes-beam-dev";

  packages = [
    erlang
    elixir
    pkgs.git
    pkgs.gnumake
    pkgs.gcc
    pkgs.nodejs_20
    pkgs.postgresql_15
    pkgs.pgvector
    pkgs.curl
    pkgs.jq
    pkgs.inotify-tools
  ];

  shellHook = ''
    export MIX_HOME=$PWD/.nix-mix
    export HEX_HOME=$PWD/.nix-hex
    export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
    export PGDATA=$PWD/.nix-pgdata
    export PGHOST=127.0.0.1
    export PGPORT=5432

    if [ ! -d "$PGDATA" ]; then
      echo "[nix develop] Initialising local Postgres cluster at $PGDATA..."
      initdb --username=postgres --auth=trust --no-locale --encoding=UTF8 "$PGDATA"
      echo "host all all 127.0.0.1/32 trust" >> "$PGDATA/pg_hba.conf"
      echo "host all all ::1/128        trust" >> "$PGDATA/pg_hba.conf"
    fi

    if ! pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
      echo "[nix develop] Starting local Postgres..."
      pg_ctl -D "$PGDATA" -l "$PGDATA/postgres.log" start
      sleep 1
      psql -U postgres -d postgres -c \
        "CREATE EXTENSION IF NOT EXISTS vector;" > /dev/null 2>&1 || true
    fi

    mix local.hex   --if-missing --force > /dev/null
    mix local.rebar --if-missing --force > /dev/null

    echo ""
    echo "  Hermes BEAM dev shell ready (flake)"
    echo "  Erlang/OTP : $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || echo unknown)"
    echo "  Elixir     : $(elixir --version | head -1)"
    echo "  Postgres   : $(psql --version)"
    echo ""
    echo "  Quick start:"
    echo "    mix deps.get && mix ecto.setup && mix test"
    echo ""
  '';
}
