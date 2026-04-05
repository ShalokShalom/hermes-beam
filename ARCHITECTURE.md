# Hermes BEAM — Architecture

This document is the authoritative deep-dive reference for the system design of Hermes BEAM. It complements `README.md` (quick-start and overview) and `ROADMAP.md` (phase planning and exit criteria). When code and this document disagree, the code is wrong.

---

## Table of Contents

1. [System Boundaries](#1-system-boundaries)
2. [Supervision Tree](#2-supervision-tree)
3. [Data Architecture](#3-data-architecture)
4. [Agent Lifecycle](#4-agent-lifecycle)
5. [LLM Tier System](#5-llm-tier-system)
6. [Distributed Cluster](#6-distributed-cluster)
7. [Memory Subsystem](#7-memory-subsystem)
8. [Skill Subsystem](#8-skill-subsystem)
9. [Synthetic Data Pipeline](#9-synthetic-data-pipeline)
10. [Observability](#10-observability)
11. [Configuration Reference](#11-configuration-reference)
12. [Failure Modes and Degradation](#12-failure-modes-and-degradation)
13. [Security Model](#13-security-model)
14. [Extension Points](#14-extension-points)

---

## 1. System Boundaries

Hermes BEAM is a **closed-loop, sovereign AI agent system**. It has exactly one external dependency boundary: HuggingFace Hub for initial model weight downloads. After first boot, the system operates entirely within your hardware — no data leaves your network unless you explicitly configure an external embedding or LLM provider.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Tailscale WireGuard Mesh                             │
│                                                                             │
│   ┌───────────────────────────┐     ┌──────────────────────────────────┐   │
│   │       CENTRAL HUB         │     │       COMPUTE WORKERS            │   │
│   │   Gaming PC               │     │   Mac Mini Pro / Base            │   │
│   │                           │     │                                  │   │
│   │  PostgreSQL + pgvector    │     │  Nx.Serving tiers (role-gated)   │   │
│   │  libcluster_postgres      │◄────│  AgentLoop Reactor workflows     │   │
│   │  Nx.Serving :tier_1       │     │  Ash AI actions                  │   │
│   │  Nx.Serving :tier_2       │     │  Scratchpad / Episodic via Ecto  │   │
│   │  IdleScheduler            │     │                                  │   │
│   │  WorkflowHandler (ETS)    │     └──────────────────────────────────┘   │
│   │  Phoenix / Livebook ◄─────┼──── browser                               │
│   └───────────────────────────┘                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                         (first boot only)
                                    │
                         HuggingFace Hub
                    (model weight downloads)
```

---

## 2. Supervision Tree

The OTP supervision tree branches at boot based on `NODE_TYPE` (`"hub"` | `"worker"`).

```
HermesBeam.Supervisor  [:one_for_one]
  ├── HermesBeam.Repo                     # all nodes
  ├── Phoenix.PubSub                      # all nodes
  ├── Ash (domain: HermesBeam.Domain)     # all nodes
  ├── Cluster.Supervisor                  # all nodes
  ├── HermesBeam.LLM.TierSupervisor       # all nodes (loads role-appropriate tiers)
  │     ├── ModelWorker (:tier_1_reasoning)   # gaming_gpu only
  │     ├── ModelWorker (:tier_2_general)     # gaming_gpu, mac_mini_pro
  │     └── ModelWorker (:tier_3_docs)        # mac_mini_pro, mac_mini_base
  ├── HermesBeam.IdleScheduler            # hub only
  └── HermesBeamWeb.Endpoint             # hub only
```

`WorkflowHandler.attach/0` is called outside the supervision tree during `Application.start/2` because `:telemetry.attach_many/4` is process-independent — it registers callbacks in a global ETS table managed by the `:telemetry` application. It is guarded against double-attachment with an `ArgumentError` rescue.

### TierSupervisor and ModelWorker

`TierSupervisor` dynamically creates one `ModelWorker` child per entry in `topology[:active_tiers]`. This list is resolved from `NODE_ROLE` at runtime in `config/runtime.exs`. Each `ModelWorker` boots asynchronously — it sends `{:load_model, ...}` to itself in `init/1` to avoid blocking the supervisor. On load failure it transitions to `:degraded` state rather than crashing, preventing the supervisor from hitting `:max_restarts`.

---

## 3. Data Architecture

All persistent state lives in a single PostgreSQL instance on the Hub. Workers access it via Ecto over the Tailscale tunnel (TLS enforced when `NODE_TYPE != "hub"`).

### Tables

| Table | Ash Resource | Purpose |
| :--- | :--- | :--- |
| `agent_scratchpads` | `HermesBeam.Memory.Scratchpad` | Bounded LLM-curated working memory (one row per agent) |
| `agent_memories` | `HermesBeam.Memory.Episodic` | Unlimited semantic memory with pgvector embeddings |
| `skills` | `HermesBeam.Skill` | LLM-generated Elixir modules, source + compiled name + usage stats |
| `workflow_logs` | `HermesBeam.WorkflowLog` | Reactor run history — step timing, status, input snapshots |

### Indexes

`agent_memories` carries an IVFFlat approximate nearest-neighbour index on `content_vector` (`lists: 100`). This index becomes effective only after approximately `3,900` rows exist; below that threshold Postgres falls back to a sequential scan, which is correct and harmless.

### Ash Domain

All four resources are registered in `HermesBeam.Domain`. Any resource not listed there cannot be queried via Ash actions and will raise `Ash.Error.Invalid.NoSuchResource` at runtime.

---

## 4. Agent Lifecycle

Every agent interaction runs as an `AgentLoop` Reactor workflow. Reactor provides:
- **Concurrency**: independent steps run in parallel
- **Saga compensation**: `undo/3` callbacks roll back side-effects on failure
- **Dynamic extension**: a step can return `{:ok, value, additional_steps}` to inject new steps at runtime

### Step Sequence

```
fetch_memories ──┐
                  ├──► build_context_prompt ──► execute_inference ──► store_reflection ──► curate_scratchpad
fetch_scratchpad ─┘
```

**fetch_memories**: Embeds the user prompt via `HERMES_EMBEDDING_MODEL` and queries `agent_memories` using pgvector cosine similarity (top 5). Degrades to `[]` on any error — a pgvector index build failure or missing embedding model does not abort the turn.

**fetch_scratchpad**: Reads the agent's bounded working memory. Returns `nil` if none exists; downstream steps handle the nil case and initialise a new scratchpad after the first turn.

**build_context_prompt**: Assembles the full LLM context from working memory + user profile + episodic memories + the current request. This is the Orient phase — translating raw observations into a structured inference prompt.

**execute_inference**: Routes to the appropriate `Nx.Serving` tier via `IntelligentRouter.tier_for/1`. If the model is in `:degraded` state, returns a labelled fallback string rather than crashing the turn. The response is always a binary — callers can detect degraded output by checking for the `"[Model unavailable"` prefix.

**store_reflection**: Persists `User: ...\nAgent: ...` as an `:reflection` type episodic memory. This is the primary mechanism by which the agent accumulates experience over time.

**curate_scratchpad**: Calls `:tier_3_docs` (Phi-3 Mini) with a condensation prompt. The LLM must return valid JSON `{"memory_text": "...", "user_text": "..."}` within the hard character limits enforced by `Scratchpad` Ash validations. On parse failure or LLM error the step returns `{:ok, :curation_skipped}` — the turn still completes, just without a scratchpad update.

---

## 5. LLM Tier System

### Tier Routing

`IntelligentRouter.tier_for/1` is a pure function (no Reactor graph, no GenServer) that maps task atom to tier atom:

| Task type | Tier | Rationale |
| :--- | :--- | :--- |
| `:deep_reflection`, `:complex_planning` | `:tier_1_reasoning` | Needs 70B parameter capacity for multi-step reasoning |
| `:synthetic_data`, `:tool_calling` | `:tier_2_general` | 8B is sufficient; avoids tying up the GPU for routine work |
| `:write_docs`, `:format_json` | `:tier_3_docs` | Phi-3 Mini is fast and accurate for structured output tasks |
| everything else | `:tier_2_general` | Safe default |

### Cross-Node Dispatch

Once an `Nx.Serving` is started under a registered name (e.g. `:tier_1_reasoning`), any node in the Erlang cluster can call `Nx.Serving.batched_run(:tier_1_reasoning, prompt)`. The BEAM VM's distributed registry forwards the call to whichever node is hosting that serving — transparently, over the Tailscale WireGuard tunnel. No additional routing code is required.

### Degraded State

A `ModelWorker` that fails to load moves to `status: :degraded`. It remains in the supervision tree in a stable non-crashing state. `generate/2` calls against a degraded worker return `{:exit, reason}` from the `catch :exit` block because the serving process never started. `AgentLoop` pattern-matches `{:error, :degraded}` and substitutes a human-readable message.

---

## 6. Distributed Cluster

### Discovery

`libcluster_postgres` uses a dedicated PostgreSQL channel (`hermes_beam_cluster`) as the cluster membership bus. Nodes write their Tailscale IP and Erlang node name to the channel on boot and subscribe for peer announcements. This co-locates the cluster fault domain with the data fault domain — if Postgres is down, the agent cannot store memory anyway.

### Node Identity

Each node's Erlang node name is `hermes@<tailscale_ip>`, set by `bin/start_node.sh` at boot. The Erlang distribution cookie is shared via the `COOKIE` environment variable.

### Worker Statefulness

Worker nodes are **fully stateless at the process level**. All state (memory, skills, workflow logs) lives in Hub Postgres. A Worker can be restarted, replaced, or added to the cluster without data loss or manual intervention.

---

## 7. Memory Subsystem

### Scratchpad (Working Memory)

Mirrors Hermes Agent's `MEMORY.md` + `USER.md` design. One row per logical agent, enforcing:
- `memory_text` ≤ 2,200 characters
- `user_text` ≤ 1,375 characters

The agent cannot append — it must overwrite. This forces consolidation and produces qualitatively better long-term behaviour. Limits are enforced at the Ash validation layer, not the application layer, so no code path can bypass them.

### Episodic Memory (Long-Term)

Unbounded growth. Each entry has:
- `content` — human-readable text
- `content_vector` — embedding vector (dimensions determined by `HERMES_EMBEDDING_MODEL`)
- `type` — one of `:observation`, `:reflection`, `:user_fact`, `:synthetic`
- `agent_id` — which logical agent owns this memory

The `:synthetic` type is created by `SyntheticDataReactor` during idle periods. Synthetic memories seed the episodic store with domain knowledge before the agent has real experience, improving early recall quality.

### Embedding Model

Resolved at runtime from `HERMES_EMBEDDING_MODEL` (default: `"local/bge-small-en-v1.5"`, 384 dimensions). To switch to a higher-quality model, update both the env var and the `dimensions` constraint in `episodic.ex`, then run a migration to rebuild the `content_vector` column and IVFFlat index.

---

## 8. Skill Subsystem

The `Skill` resource stores LLM-generated Elixir code. The `CompileSkillModule` Ash Change compiles it on create:

1. Sanitises the skill name via `Macro.camelize/1` to produce a valid module name segment
2. Wraps the code in `defmodule HermesBeam.Skills.Dynamic.<Name> do ... end`
3. Purges any existing version of the module from the code server
4. Calls `Code.compile_string/1` inside a `try/rescue` covering all three Elixir compile error types
5. On success: stores the module atom string in `skill.module_name`
6. On failure: adds an Ash changeset error so the calling Reactor step can trigger its `undo/3` compensation (typically: re-prompt the LLM with the error)

Skills are callable at runtime via `apply(String.to_existing_atom(skill.module_name), :run, [args])`.

---

## 9. Synthetic Data Pipeline

`IdleScheduler` runs only on Hub nodes. Every 5 minutes it checks whether any `AgentLoop` workflow has started in the last 10 minutes by querying `workflow_logs`. If idle, it round-robins through a 10-concept pool and dispatches `SyntheticDataReactor` in an unsupervised `Task`.

`SyntheticDataReactor` (4 steps):
1. **build_prompt** — structures a generation prompt requesting 3 realistic scenarios
2. **generate_scenarios** — sends to `:tier_2_general` (Llama 3 8B)
3. **parse_scenarios** — strips markdown code fences, `Jason.decode/1`, validates list of strings; compensates by logging and returning `[]` rather than failing the graph
4. **store_scenarios** — batch-creates `:synthetic` episodic memories; emits `[:hermes_beam, :synthetic, :generated]` telemetry

All synthetic memories are attributed to the `SYNTHETIC_AGENT_ID` (a fixed UUIDv4 configured in `runtime.exs`). This keeps synthetic and real agent memories queryable independently.

---

## 10. Observability

### WorkflowLog + WorkflowHandler

`WorkflowHandler` is a `:telemetry` handler attached on **every node** at boot. It captures four Reactor events:

| Event | Action |
| :--- | :--- |
| `[:reactor, :run, :start]` | Creates a `WorkflowLog` row, stores `reactor_id → log_id` in node-local ETS |
| `[:reactor, :step, :run, :start]` | Merges step start time into `workflow_log.steps` map |
| `[:reactor, :step, :run, :stop]` | Merges step finish time and status into `workflow_log.steps` map |
| `[:reactor, :run, :stop]` | Marks log as `:completed` or `:failed`, deletes ETS entry |

All Reactor lifecycle events for a given run fire on the node that called `Reactor.run/3`. The ETS lookup is therefore always local. The Postgres write happens over Ecto — which on Worker nodes goes via Tailscale to the Hub's Postgres instance.

### Livebook Dashboard

Livebook is started externally and **attached** to the running Hub node via `--attach` mode. It becomes a sibling Erlang process in the same distribution mesh. Every notebook cell is a direct Elixir function call — `Ash.read!`, `Reactor.run`, `:ets.tab2list`, `Node.list()` — with zero additional infrastructure.

Connection scripts:
- `bin/livebook_connect.sh` — dev (localhost) and prod (Tailscale remote) modes
- Notebook: `notebooks/hermes_beam.livemd` — 6 sections covering all subsystems

---

## 11. Configuration Reference

### Required Environment Variables

| Variable | Default | Required On | Purpose |
| :--- | :--- | :--- | :--- |
| `NODE_TYPE` | `"worker"` | all nodes | `"hub"` or `"worker"` |
| `NODE_ROLE` | `"mac_mini_base"` | all nodes | Hardware tier: `"gaming_gpu"`, `"mac_mini_pro"`, `"mac_mini_base"` |
| `HUB_IP` | `"127.0.0.1"` | worker nodes | Tailscale IP of the Hub machine |
| `DB_USER` | `"postgres"` | all nodes | Postgres username |
| `DB_PASS` | `"postgres"` | all nodes | Postgres password |
| `DB_NAME` | `"hermes_beam"` | all nodes | Postgres database name |
| `COOKIE` | — | all nodes | Shared Erlang distribution cookie |
| `SYNTHETIC_AGENT_ID` | — | hub nodes | Fixed UUIDv4 for synthetic memory agent |
| `HUGGING_FACE_HUB_TOKEN` | — | all nodes | Token for gated HuggingFace models |
| `SECRET_KEY_BASE` | — | hub, prod only | Phoenix endpoint signing key |

### Optional Environment Variables

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `HERMES_EMBEDDING_MODEL` | `"local/bge-small-en-v1.5"` | Embedding model for episodic memory |
| `POOL_SIZE` | `"10"` | Ecto connection pool size |
| `PORT` | `"4000"` | Phoenix HTTP port (prod only) |
| `OPENAI_API_KEY` | — | Optional: enables cloud LLM fallback via ash_ai |

### Generate SYNTHETIC_AGENT_ID

```bash
mix run -e 'IO.puts(Ecto.UUID.generate())'
# Copy the output and set: export SYNTHETIC_AGENT_ID="<uuid>"
```

---

## 12. Failure Modes and Degradation

| Failure | Behaviour | Recovery |
| :--- | :--- | :--- |
| Model load fails (OOM, wrong CUDA) | `ModelWorker` moves to `:degraded`; supervisor stable | Fix hardware/config, restart worker process |
| Degraded model called in AgentLoop | Returns `"[Model unavailable: ...]"` string; turn completes | Restart ModelWorker or reconfigure tier |
| Episodic recall fails (no index yet) | `fetch_memories` returns `[]`; turn completes without context | Wait for IVFFlat index to warm up (~3,900 rows) |
| Scratchpad curation LLM output invalid | `curate_scratchpad` returns `:curation_skipped`; turn completes | LLM will succeed on next turn; no data loss |
| Synthetic scenario parse fails | `parse_scenarios` compensates; logs warning, batch skipped | IdleScheduler retries on next idle cycle |
| Postgres unreachable | Ecto connection failure; all Ash actions fail | Restore Postgres; all processes auto-reconnect |
| Worker node crashes | Supervisor restarts processes; state in Postgres is intact | Automatic; no manual intervention |
| Hub node crashes | Postgres and cluster coordinator gone; workers degrade | Restart Hub; workers reconnect via libcluster_postgres |

---

## 13. Security Model

**Network**: All inter-node Erlang distribution traffic travels over the Tailscale WireGuard mesh. TLS is enforced on the Ecto connection for Worker → Hub Postgres traffic (`ssl: true` when `NODE_TYPE != "hub"`).

**Erlang cookie**: The distribution cookie is the only authentication mechanism between nodes. It must be kept secret and consistent across the cluster. Rotate it by restarting all nodes with a new `COOKIE` value simultaneously.

**Dynamic code compilation**: `Code.compile_string/1` in `CompileSkillModule` runs LLM-generated code with full BEAM VM privileges. This is acceptable for a private home lab. For multi-tenant deployments, skills should be sandboxed — the WASM (wasmCloud/AtomVM) approach is tracked in `ROADMAP.md` Future Considerations.

**Embedding model**: `HERMES_EMBEDDING_MODEL` is read at runtime. Never point this at a hosted API unless you intend for your episodic memory content to leave your network.

---

## 14. Extension Points

| Capability | How to extend |
| :--- | :--- |
| Add a new LLM tier | Add entry to `loaded_tiers` in `runtime.exs`; add routing clause in `IntelligentRouter.tier_for/1` |
| Add a new memory type | Add atom to `Episodic.type` constraint; update queries as needed |
| Add a new Reactor workflow | `use Reactor` in `lib/hermes_beam/workflows/`; register telemetry automatically picks it up |
| Add a new Ash resource | Create resource file; register in `HermesBeam.Domain`; generate migration |
| Swap embedding model | Set `HERMES_EMBEDDING_MODEL`; update `dimensions` in `episodic.ex`; run migration to rebuild vector column |
| Add Phoenix LiveView panels | See ROADMAP.md Phase 7-LV — Livebook sections map 1:1 to planned LiveView components |
| Expand synthetic concept pool | Add strings to `@concept_pool` in `IdleScheduler`; takes effect on next idle cycle |
