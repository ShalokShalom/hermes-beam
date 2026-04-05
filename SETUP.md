# Hermes BEAM — Setup & Testing Guide

This guide gets you from a clean machine to a running test suite.
It covers three paths:

| Path | Section |
| :--- | :--- |
| **NixOS** (recommended) | [§ NixOS — shell.nix / nix develop](#nixos) |
| **Other Linux or macOS — Lix** | [§ Installing Lix](#installing-lix) |
| **Without Nix** (asdf / mise fallback) | [§ Non-Nix Fallback](#non-nix-fallback) |

All three paths converge at [§ Project Setup](#project-setup).

---

## Prerequisites (all paths)

The only hard external requirement is **PostgreSQL 15+ with the `pgvector` extension**.
Everything else (Erlang, Elixir, Node.js) is managed by the chosen toolchain.

### PostgreSQL + pgvector

**NixOS / Nix** — handled automatically by `shell.nix` / `nix develop`.

**Ubuntu / Debian:**
```bash
sudo apt update
sudo apt install -y postgresql-15 postgresql-server-dev-15 git build-essential

# Install pgvector from source (apt package often lags)
git clone --branch v0.7.4 https://github.com/pgvector/pgvector.git
cd pgvector
make
sudo make install
cd ..

sudo systemctl enable --now postgresql
sudo -u postgres psql -c "CREATE USER postgres WITH SUPERUSER PASSWORD 'postgres';"
```

**Fedora / RHEL / Rocky:**
```bash
sudo dnf install -y postgresql-server postgresql-devel git gcc make
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql

git clone --branch v0.7.4 https://github.com/pgvector/pgvector.git
cd pgvector && make && sudo make install && cd ..

sudo -u postgres psql -c "CREATE USER postgres WITH SUPERUSER PASSWORD 'postgres';"
```

**macOS (Homebrew):**
```bash
brew install postgresql@15 pgvector
brew services start postgresql@15
createuserpostgres --superuser postgres 2>/dev/null || true
psql postgres -c "ALTER USER postgres WITH PASSWORD 'postgres';"
```

---

## NixOS

The project ships both a classic `shell.nix` (for `nix-shell`) and a
`nix/devshell.nix` (for `nix develop` with flakes).
Both provide identical environments.

### Using `nix-shell` (no flakes needed)

```bash
git clone https://github.com/ShalokShalom/hermes-beam.git
cd hermes-beam
nix-shell        # drops you into an env with Elixir 1.16 / OTP 26 / Node 20
```

### Using `nix develop` (flakes)

If your NixOS config has `experimental-features = nix-command flakes` enabled:

```bash
git clone https://github.com/ShalokShalom/hermes-beam.git
cd hermes-beam
nix develop ./nix#devshell
```

### Using `direnv` (recommended for daily work)

```bash
# One-time NixOS setup
nix-env -iA nixos.direnv  # or add direnv to environment.systemPackages
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc   # or your shell's rc file

# In the project directory
echo 'use nix' > .envrc   # for nix-shell, or 'use flake ./nix#devshell' for flakes
direnv allow
```

The shell activates automatically every time you `cd` into the project.

---

## Installing Lix

[Lix](https://lix.systems) is a fork of Nix maintained by the community,
with better error messages, faster evaluation, and first-class flake support.
Use it on any Linux distribution or macOS in place of upstream Nix.

> **Why Lix over Nix?** Lix has cleaner CLI UX, safer default sandbox settings,
> and the same package set as nixpkgs — the `shell.nix` in this repo works
> identically with both.

### Step 1 — Install Lix

**Linux (single-user or multi-user):**
```bash
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
```

This installs the Lix daemon, creates `/nix`, and adds shell hooks to your profile.
Close and reopen your terminal, or run:
```bash
. ~/.nix-profile/etc/profile.d/nix.sh
```

**macOS:**
```bash
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
```

macOS requires a synthetic APFS volume at `/nix` on macOS 10.15+.
The installer creates this automatically and adds it to `/etc/synthetic.conf`.
A **single reboot** is required after installation.

### Step 2 — Enable flakes (optional but recommended)

Lix ships with flakes enabled by default.
If you chose to disable them manually, re-enable them:

```bash
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

### Step 3 — Verify

```bash
nix --version         # should print "nix (Lix, Like Nix) 2.91.x" or similar
nix-shell --version   # should print the same
```

### Step 4 — Enter the dev shell

```bash
git clone https://github.com/ShalokShalom/hermes-beam.git
cd hermes-beam
nix-shell             # classic shell.nix
# or
nix develop ./nix#devshell   # flake-based
```

### Lix — Troubleshooting

| Symptom | Fix |
| :--- | :--- |
| `nix: command not found` after install | Run `. ~/.nix-profile/etc/profile.d/nix.sh` or restart shell |
| macOS: `/nix` not writable | Reboot — the APFS synthetic volume is created at boot |
| `error: experimental feature 'flakes' is disabled` | Add `experimental-features = nix-command flakes` to `~/.config/nix/nix.conf` |
| `SSL peer certificate` errors behind a proxy | Set `NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` |
| Permission denied on `/nix/store` (multi-user) | Ensure the `nix-daemon` service is running: `sudo systemctl start nix-daemon` |

---

## Non-Nix Fallback

Use [mise](https://mise.jdx.dev) (or asdf) to install the exact toolchain
versions pinned in `.tool-versions`.

### mise (recommended)

```bash
# Install mise
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
# Restart your shell, then:

git clone https://github.com/ShalokShalom/hermes-beam.git
cd hermes-beam
mise install          # reads .tool-versions, installs Elixir 1.16.3-otp-26 + Erlang 26.2.5
```

### asdf

```bash
asdf plugin add erlang
asdf plugin add elixir
asdf install          # reads .tool-versions
```

> **Note:** Elixir 1.16 requires Erlang/OTP 24–26. The `.tool-versions` pins
> OTP 26, which is the tested version. Using a different OTP version may cause
> `mix compile` warnings or distributed-node incompatibilities.

---

## Project Setup

Everything from here is identical regardless of which toolchain path you took.

### 1 — Install Hex and rebar

```bash
mix local.hex --force
mix local.rebar --force
```

### 2 — Fetch dependencies

```bash
mix deps.get
```

### 3 — Configure the test database

The test config (`config/test.exs`) expects Postgres on `localhost:5432` with
username `postgres` / password `postgres`.
The dev config (`config/dev.exs`) expects the same for `hermes_beam_dev`.

Create and migrate both databases:

```bash
# Creates hermes_beam_dev and hermes_beam_test, runs all migrations
mix ecto.setup
```

If you want to reset from scratch:

```bash
mix ecto.reset
```

### 4 — Generate a synthetic agent ID

The `IdleScheduler` (Hub-only) requires a stable UUID. For local dev and test
this is only needed if you intend to boot the full application — the test suite
does not require it. For `mix run` / `iex -S mix`:

```bash
export SYNTHETIC_AGENT_ID=$(mix run --no-start -e 'IO.puts(Ecto.UUID.generate())')
```

Add it permanently to your shell profile or `.envrc` to avoid repeating this.

### 5 — Set NODE_TYPE and NODE_ROLE

For single-node local testing, run as a Hub node with the base Mac Mini profile
(no GPU required — tier 3 only, using Phi-3 Mini):

```bash
export NODE_TYPE=hub
export NODE_ROLE=mac_mini_base
```

To skip ML model loading entirely during pure unit/integration testing, these
are not required — the test suite does not boot the application supervisor.

---

## Running the Tests

### Full test suite

```bash
mix test
```

`mix test` automatically creates and migrates the test database on first run
via the `test` alias in `mix.exs`.

### Specific test file

```bash
mix test test/hermes_beam/changes/compile_skill_module_test.exs
mix test test/hermes_beam/memory/scratchpad_test.exs
```

### Verbose output

```bash
mix test --trace
```

### Parallel partitions (CI)

```bash
MIX_TEST_PARTITION=1 mix test
MIX_TEST_PARTITION=2 mix test
```

---

## Running the Application (Single Node Dev)

```bash
export NODE_TYPE=hub
export NODE_ROLE=mac_mini_base
export SYNTHETIC_AGENT_ID=<your-uuid>

iex -S mix
```

This boots the full supervisor tree on a single node: Repo, PubSub, libcluster,
TierSupervisor (loads Phi-3 Mini into EXLA), IdleScheduler, and the Phoenix endpoint.

> **Note:** `TierSupervisor` will attempt to download Phi-3 Mini from HuggingFace
> on first boot (~2.4 GB). Set `HF_TOKEN` if you have a HuggingFace account to
> avoid rate-limit errors on model downloads:
> ```bash
> export HF_TOKEN=hf_...
> ```

### Interactive agent turn

Once `iex -S mix` is running:

```elixir
# First create a scratchpad for your test agent
agent_id = Ecto.UUID.generate()

HermesBeam.Memory.Scratchpad
|> Ash.Changeset.for_create(:initialize, %{
  agent_id: agent_id,
  memory_text: "Test agent initialized.",
  user_text: "Testing Hermes BEAM locally."
})
|> Ash.create!()

# Run a full agent turn
Reactor.run(
  HermesBeam.Workflows.AgentLoop,
  %{agent_id: agent_id, user_prompt: "Hello! What can you do?", task_type: :general}
)
```

---

## Livebook Dashboard (Optional)

If you have Livebook installed:

```bash
bash bin/livebook_connect.sh
```

Open the URL printed in the terminal, then open `notebooks/hermes_beam.livemd`.
The runtime is pre-attached to the running Hub node — all cells execute live
against your local cluster.

To install Livebook via Nix:

```bash
# Inside the project nix-shell:
nix-env -iA nixpkgs.livebook   # system-wide
# or run it directly without installing:
nix run nixpkgs#livebook
```

---

## Environment Variable Reference

| Variable | Required | Default | Description |
| :--- | :--- | :--- | :--- |
| `NODE_TYPE` | dev/prod | `worker` | `hub` or `worker` |
| `NODE_ROLE` | dev/prod | `mac_mini_base` | Hardware tier for model loading |
| `HUB_IP` | workers only | `127.0.0.1` | Tailscale IP of the Hub node |
| `SYNTHETIC_AGENT_ID` | hub only | — | Stable UUID for synthetic memories |
| `HERMES_EMBEDDING_MODEL` | optional | `local/bge-small-en-v1.5` | Embedding model (384-dim default) |
| `HF_TOKEN` | optional | — | HuggingFace token for gated models |
| `DB_USER` | optional | `postgres` | Postgres username |
| `DB_PASS` | optional | `postgres` | Postgres password |
| `DB_NAME` | optional | `hermes_beam` | Postgres database name |
| `POOL_SIZE` | optional | `10` | Ecto connection pool size |
| `SECRET_KEY_BASE` | prod only | — | Phoenix secret key (64+ chars) |

---

## Common Errors

| Error | Cause | Fix |
| :--- | :--- | :--- |
| `could not connect to the server` | Postgres not running | `sudo systemctl start postgresql` or `brew services start postgresql@15` |
| `extension "vector" does not exist` | pgvector not installed | See PostgreSQL + pgvector section above |
| `extension "uuid-ossp" does not exist` | Postgres missing contrib | Install `postgresql-contrib` package |
| `SYNTHETIC_AGENT_ID is not set` | Missing env var | Run the `export SYNTHETIC_AGENT_ID=...` command in [Step 4](#4--generate-a-synthetic-agent-id) |
| `(UndefinedFunctionError) EXLA.Backend` | EXLA not compiled | Run `mix deps.compile exla` — may take 10–15 min on first compile |
| `model download failed 401` | HuggingFace gated model | Set `HF_TOKEN=hf_...` |
| `dimensions mismatch` | Wrong `HERMES_EMBEDDING_MODEL` | The model and `dimensions:` in `episodic.ex` must match. Default is 384. |
