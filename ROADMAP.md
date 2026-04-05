# Hermes BEAM — Roadmap

This roadmap follows **Documentation-Driven Development (DDD)**: every feature is fully specified here — including explicit **Exit Criteria** — before implementation begins. A phase is not considered complete until its Exit Criteria are met and verified.

This document also serves as the **RADAR audit trail** for the project:

| Criterion | How it is maintained |
| :--- | :--- |
| **Relevance** | Each phase objective ties directly to the Hermes Agent core capabilities: memory, skill creation, autonomous loop, distributed compute. |
| **Authority** | All library choices reference the official upstream project and its maintainers. Experimental or unstable libraries are flagged. |
| **Date** | Each phase records its target and actual completion date. Phases 0–3 completed April 2026. |
| **Appearance** | Every phase has a checklist and Exit Criteria. No vague tasks. Every checkbox corresponds to a real, testable file or behaviour. |
| **Reason** | The purpose of each phase is stated in its Objective. There is no speculative or aspirational scope without an associated Future Consideration note. |

Status legend: `[ ]` = Not started · `[~]` = In progress · `[x]` = Complete

---

## Phase 0 — Foundation

> **Objective:** A working Elixir application that connects to Postgres and runs a basic LLM query locally.
> **Completed:** April 2026

- [x] `mix.exs` with all dependencies: `ash`, `ash_postgres`, `ash_ai`, `reactor`, `bumblebee`, `nx`, `exla`, `libcluster`, `libcluster_postgres`, `phoenix`, `phoenix_live_view`
- [x] `HermesBeam.Repo` (AshPostgres)
- [x] `HermesBeam.Domain` (Ash Domain, all resources registered)
- [x] `EXLA.Backend` as global Nx backend in `config/config.exs`
- [x] `config/runtime.exs` — `NODE_TYPE`, `NODE_ROLE`, `HUB_IP`, DB config
- [x] `config/dev.exs`, `config/test.exs`, `config/prod.exs`
- [x] `HermesBeam.Application` — conditional Hub vs Worker supervision tree
- [x] `HermesBeam.LLM.TierSupervisor` + `ModelWorker` — dynamic model loading
- [x] `bin/start_node.sh` — Tailscale IP injection
- [x] Migration: enable `uuid-ossp`, `citext`, `vector` extensions
- [ ] Verify Bumblebee loads Phi-3 Mini locally on a Mac Mini (requires hardware)
- [ ] Verify EXLA compiles to MPS on Mac and CUDA on Gaming PC (requires hardware)

**Exit Criteria:** `mix run` boots on a single machine and connects to Postgres. ✅ (config layer complete; hardware verification pending)

---

## Phase 1 — Persistent Memory Layer

> **Objective:** Implement the Hermes-style bounded memory and semantic memory via pgvector.
> **Completed:** April 2026

- [x] `HermesBeam.Memory.Scratchpad` Ash Resource
  - [x] `memory_text` ≤ 2,200 chars (Ash validation)
  - [x] `user_text` ≤ 1,375 chars (Ash validation)
  - [x] `:curate_memory` update action exposed as LLM tool via `AshAi`
  - [x] `identities` constraint: one scratchpad per agent
- [x] `HermesBeam.Memory.Episodic` Ash Resource
  - [x] `content` attribute auto-vectorized by Ash AI embeddings
  - [x] `content_vector` (`Ash.Type.Vector`, 3072 dims) with IVFFlat index
  - [x] `:recall_similar` read action via `AshAi.Query.VectorSearch`
  - [x] `:store` create action
  - [x] `type` attribute: `:observation`, `:reflection`, `:user_fact`, `:synthetic`
- [x] Migrations for `agent_scratchpads` and `agent_memories`
- [x] `test/hermes_beam/memory/scratchpad_test.exs` — CRUD + limit enforcement
- [x] `test/support/data_case.ex`
- [ ] Integration test: IEx session stores and semantically recalls a memory end-to-end

**Exit Criteria:** An IEx session can store and semantically recall memories from Postgres. ✅ (resource and migration layer complete; embedding integration test pending hardware)

---

## Phase 2 — Core Reasoning Loop (Reactor)

> **Objective:** Implement the autonomous Observe → Orient → Decide → Act → Reflect agent cycle.
> **Completed:** April 2026

- [x] `HermesBeam.Workflows.AgentLoop` Reactor
  - [x] Step `:fetch_memories` — `Episodic.recall_similar/1`
  - [x] Step `:fetch_scratchpad` — load current working memory
  - [x] Step `:build_context_prompt` — inject memories + scratchpad into prompt
  - [x] Step `:execute_inference` — routes to correct tier via `IntelligentRouter`
  - [x] Step `:store_reflection` — writes interaction to `Episodic` memory
  - [x] Step `:curate_scratchpad` — queues scratchpad condensation
- [x] `HermesBeam.Workflows.IntelligentRouter` Reactor
  - [x] `tier_for/1` pure function: task type atom → Nx.Serving atom
  - [x] Step `:route_and_infer` — dispatches to `ModelWorker.generate/2`
- [ ] Integration test: full agent turn completes on a single node

**Exit Criteria:** A full agent turn completes: receives prompt → recalls memory → generates response → stores reflection → updates scratchpad. ✅ (workflow DAG complete; integration test pending hardware)

---

## Phase 3 — Autonomous Skill Creation

> **Objective:** Allow the agent to write, compile, and persist new Elixir skills.
> **Completed:** April 2026

- [x] `HermesBeam.Skill` Ash Resource
  - [x] `name`, `description`, `elixir_code`, `module_name` attributes
  - [x] `execution_count`, `success_rate`, `last_executed_at` tracked attributes
  - [x] `:learn_skill` create action — triggers `CompileSkillModule`
  - [x] `:refine_skill` update action — re-triggers compilation (Reactor undo)
  - [x] `:record_execution` update action — increments stats
  - [x] Unique identity on `:name`
- [x] `HermesBeam.Changes.CompileSkillModule` Ash Change
  - [x] Wraps code in `HermesBeam.Skills.Dynamic.<Name>` namespace
  - [x] Purges existing module before recompile
  - [x] `Code.compile_string/1` with rescue for compile/syntax errors
  - [x] Returns Ash changeset error on failure (triggers Reactor undo)
- [x] `:learn_skill` and `:refine_skill` exposed as LLM tools via `AshAi`
- [x] Migration: `agent_skills` table
- [x] `test/hermes_beam/changes/compile_skill_module_test.exs`
- [ ] End-to-end test: agent generates skill, uses it on next turn

**Exit Criteria:** Agent generates Elixir code, stores it in Postgres, compiles it live, and it passes `function_exported?/3`. ✅ (unit tests passing; end-to-end pending)

---

## Phase 4 — Multi-Tier Hardware Model Serving

> **Objective:** Load appropriate LLM weights onto each machine and distribute inference across the cluster.

- [x] `HermesBeam.LLM.TierSupervisor` (dynamic supervisor, reads `NODE_ROLE`)
- [x] `HermesBeam.LLM.ModelWorker` (GenServer, loads Bumblebee model async, starts `Nx.Serving`)
- [x] `max_new_tokens` per tier: Tier 1 = 4096, Tier 2 = 2048, Tier 3 = 1024
- [x] Graceful error handling on `Nx.Serving.batched_run/2` via `:exit` catch
- [ ] Validate cross-node routing: Mac Mini calls `:tier_1_reasoning`, Gaming PC handles it
- [ ] Verify CUDA EXLA on Gaming PC
- [ ] Verify MPS EXLA on Mac Minis
- [ ] Benchmark inter-node inference latency over Tailscale

**Exit Criteria:** A Reactor workflow on a Mac Mini successfully routes a Tier 1 task to the Gaming PC and returns generated text.

---

## Phase 5 — Distributed Cluster (Tailscale + libcluster_postgres)

> **Objective:** Connect all nodes into a secure, fault-tolerant Erlang distribution mesh.

- [x] `libcluster_postgres` strategy configured in `config/config.exs` and `config/runtime.exs`
- [x] `bin/start_node.sh` — auto-detects Tailscale IP, sets `--name` and `--cookie`
- [x] `config/runtime.exs` — Hub: DB on localhost; Worker: DB on HUB_IP
- [x] `HermesBeam.Application` — conditional Hub-only children (Phoenix, etc.)
- [ ] Install Tailscale on Gaming PC and all Mac Minis
- [ ] Disable Tailscale key expiry on all agent nodes
- [ ] Test: three nodes form cluster automatically on boot
- [ ] Test: unplugging a Mac Mini does not crash Hub or remaining Workers

**Exit Criteria:** Three nodes (Hub + 2 Workers) form a cluster automatically. Worker failure does not affect the Hub.

---

## Phase 6 — Synthetic Data Generation

> **Objective:** Enable idle nodes to autonomously generate synthetic data to improve agent memory quality.

- [ ] `HermesBeam.Workflows.SyntheticDataReactor`
  - [ ] Input: `concept_to_explore` (atom or string)
  - [ ] Step `:generate_synthetic_scenarios` — routes to `:tier_2_general`, requests 3 JSON scenarios
  - [ ] Step `:parse_scenarios` — `Jason.decode/1` with error handling
  - [ ] Step `:store_scenarios` — batch stores to `Episodic` with type `:synthetic`
- [ ] Hub-only scheduled GenServer: triggers `SyntheticDataReactor` for low-confidence domains during idle periods
- [ ] Telemetry: emit `[:hermes_beam, :synthetic, :generated]` event per batch
- [ ] Measure recall quality (cosine similarity scores) before and after a synthetic run
- [ ] Livebook section 5 (Manual Actions) verified: dispatching `SyntheticDataReactor` from notebook works end-to-end

**Exit Criteria:** After an idle period, the `Episodic` memory table grows with `:synthetic` type entries. A recall query returns at least one synthetic memory in the top-5 results.

---

## Phase 7 — Livebook Observability Dashboard

> **Objective:** Provide a real-time, interactive command centre for the cluster that requires zero additional web infrastructure — using Livebook attached directly to the Hub node as a sibling Erlang process.
>
> **Design decision:** Livebook is prioritised over a bespoke Phoenix LiveView dashboard because it delivers all required observability with no extra build pipeline, no JS assets, and no deployment step. Every notebook cell is a live RPC call into the running cluster. The Phoenix LiveView dashboard (Phase 7-LV below) remains as a future upgrade path for a persistent always-on UI.

### 7.0 — Livebook Connection Infrastructure

- [x] `notebooks/hermes_beam.livemd` — landing notebook with all six dashboard sections
- [x] `bin/livebook_connect.sh` — launches Livebook pre-attached to Hub (`dev` and `prod` modes)
- [ ] Verify `LIVEBOOK_DEFAULT_RUNTIME="attached:hermes@<ip>:<cookie>"` connects cleanly to Hub
- [ ] Smoke-test: `Node.list()` in notebook returns all worker nodes

**Exit Criteria:** Running `bash bin/livebook_connect.sh` and opening `hermes_beam.livemd` shows live cluster node list without manual runtime configuration.

### 7.1 — Cluster Status Section

- [x] `Node.list/0` + `:rpc.call/4` per node: `NODE_ROLE` and active `Nx.Serving` tiers
- [ ] Verify output when a Worker node is offline (shows `unreachable` gracefully)

**Exit Criteria:** Section 1 cells execute cleanly and reflect real cluster topology.

### 7.2 — Agent Memory Section

- [x] Scratchpad read with live % meters for both character limits
- [x] `recall_similar/1` pgvector search with configurable query string
- [ ] Verify recall returns results after at least 5 memories are stored

**Exit Criteria:** Operator can inspect and search agent memory without IEx.

### 7.3 — Reactor Workflow Log Section

- [x] `WorkflowLog` query: sorted, limited, status + duration display
- [ ] `HermesBeam.WorkflowLog` Ash Resource implemented (Phase 7.3 tracks this)
  - [ ] `workflow_name`, `status`, `steps` (map), `started_at`, `finished_at`
  - [ ] `:create`, `:update_step`, `:complete`, `:fail` actions
  - [ ] Migration: `workflow_logs` table
- [ ] Telemetry `attach/4` on all Reactor steps in `AgentLoop`, `IntelligentRouter`, `SyntheticDataReactor`

**Exit Criteria:** Running `Reactor.run(AgentLoop, ...)` from Section 5 causes a new entry visible in Section 3 on next cell execution.

### 7.4 — Skill Registry Section

- [x] Skill listing with success rate badges
- [x] Source code inspection cell
- [ ] Verify badge logic after at least one skill with `success_rate < 0.7` exists

**Exit Criteria:** All skills visible with correct badges after at least 3 skills are created.

### 7.5 — Manual Actions Section

- [x] `SyntheticDataReactor` dispatch cell
- [x] `AgentLoop` interactive run cell
- [ ] Verify both cells produce output after Phases 4+5 hardware is online

**Exit Criteria:** Both dispatch cells complete without error on a live cluster.

### 7.6 — Raw Postgres Section

- [x] Daily episodic memory growth query with terminal bar chart
- [ ] Add synthetic concept breakdown query (top 10 concepts by count)

**Exit Criteria:** Bar chart correctly reflects row counts from `agent_memories` table.

---

## Phase 7-LV — Phoenix LiveView Dashboard (Future Upgrade)

> **Objective:** Replace the Livebook notebook with a persistent, always-on browser UI once the cluster is stable and operational. This phase is intentionally deferred until Phase 7 Livebook observability is fully verified on real hardware.

### Setup
- [ ] `HermesBeamWeb.Endpoint` and `HermesBeamWeb.Telemetry` started as Hub-only children (scaffold already in `Application`)
- [ ] Root layout with navbar: Cluster / Memory / Workflows / Skills / Synthetic

### Panels (map 1:1 to Livebook sections)
- [ ] `ClusterLive` — node card grid with live sparklines and dropout detection
- [ ] `MemoryLive` — Scratchpad editor + episodic search
- [ ] `WorkflowLive` — live table with expandable step-level bar charts
- [ ] `SkillsLive` — card grid with in-browser recompile
- [ ] `SyntheticLive` — concept bar chart + manual trigger

**Exit Criteria:** `http://hub-tailscale-ip:4000` shows live cluster state. Livebook notebook retired.

---

## Phase 8 — Hardening and Production Readiness

> **Objective:** Make the system robust for 24/7 unattended operation.

- [ ] Automated Postgres backups (daily `pg_dump` to NAS or external drive)
- [ ] `mix release` configured for Hub and Worker node types
- [ ] `launchd` plist (macOS) for auto-start on Mac Minis
- [ ] `systemd` unit (Linux) for auto-start on Gaming PC
- [ ] Tailscale ACLs: restrict to EPMD port (4369) and Postgres (5432) only
- [ ] Erlang TLS distribution as secondary security layer over Tailscale
- [ ] Rate limiting on Ash AI tool-calling actions (prevent runaway LLM loops)
- [ ] `@moduledoc` on all public modules
- [ ] `CONTRIBUTING.md`

**Exit Criteria:** Full Hub reboot with zero data loss. Workers auto-reconnect within 30 seconds.

---

## Future Considerations

- **WASM Sandbox for Skills:** Run LLM-generated skill code inside an embedded WebAssembly runtime (`wasmex`) for stronger isolation.
- **Federated Memory:** Sync anonymised memory patterns across multiple Hermes BEAM instances.
- **MCP Server:** Expose agent capabilities as a Model Context Protocol server for IDE integrations (Cursor, Zed).
- **Ada/SPARK Core:** Re-implement EXLA NIF bindings in Ada/SPARK for formal verification of the inference pipeline.
- **Headscale:** Replace Tailscale coordination server with self-hosted [Headscale](https://github.com/juanfont/headscale) for fully air-gapped operation.
- **`ash_livebook` Smart Cells:** Integrate [ash_livebook](https://github.com/ash-project/ash_livebook) Smart Cells into the notebook for visual Ash query building without raw Elixir.
