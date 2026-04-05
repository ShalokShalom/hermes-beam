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
  - [x] `:refine_skill` update action — re-triggers compilation (called from Reactor undo)
  - [x] `:record_execution` update action — increments stats
  - [x] Unique identity on `:name`
- [x] `HermesBeam.Changes.CompileSkillModule` Ash Change
  - [x] Wraps code in `HermesBeam.Skills.Dynamic.<Name>` namespace
  - [x] Purges existing module version before recompile
  - [x] `Code.compile_string/1` with rescue for `CompileError`, `SyntaxError`, `TokenMissingError`
  - [x] Returns Ash changeset error on failure (triggers Reactor undo)
- [x] `:learn_skill` and `:refine_skill` exposed as LLM tools via `AshAi`
- [x] Migration: `agent_skills` table
- [x] `test/hermes_beam/changes/compile_skill_module_test.exs` — valid + invalid code
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
- [ ] Hub-only scheduled GenServer: triggers `SyntheticDataReactor` for low-confidence concept domains during idle periods
- [ ] Telemetry: emit `[:hermes_beam, :synthetic, :generated]` event per batch
- [ ] Measure recall quality (cosine similarity scores) before and after a synthetic run

**Exit Criteria:** After an idle period, the `Episodic` memory table grows with `:synthetic` type entries. A recall query returns at least one synthetic memory in top-5 results.

---

## Phase 7 — Phoenix LiveView Dashboard

> **Objective:** A real-time, browser-based command centre on the Hub node covering cluster health, agent memory, workflow execution, skill evolution, and synthetic data progress.

### 7.0 — Project Setup

- [ ] Add `phoenix`, `phoenix_live_view`, `phoenix_html`, `esbuild`, `tailwind` (already in `mix.exs`)
- [ ] `HermesBeamWeb.Endpoint`, `HermesBeamWeb.Telemetry` started as Hub-only children
- [ ] Root layout (`root.html.heex`) with navbar: Cluster / Memory / Workflows / Skills / Synthetic
- [ ] Tailwind CSS configured

**Exit Criteria:** `http://hub-tailscale-ip:4000` returns a styled HTML page with navigation.

### 7.1 — Cluster Health Dashboard

- [ ] `HermesBeamWeb.Live.ClusterLive` (`/dashboard/cluster`)
- [ ] Node card grid: name, Tailscale IP, `NODE_ROLE`, online/degraded status
- [ ] `Nx.Serving` table per node: tier, batch count, model repo
- [ ] Live sparkline: inference requests/min via Telemetry
- [ ] `HermesBeam.Telemetry.NodeMetrics` GenServer — polls + broadcasts via PubSub every 2s
- [ ] Node card turns red within 5s of dropout (no refresh)

**Exit Criteria:** Unplugging a Mac Mini causes its card to turn red within 5 seconds.

### 7.2 — Agent Memory Explorer

- [ ] `HermesBeamWeb.Live.MemoryLive` (`/dashboard/memory`)
- [ ] Scratchpad: side-by-side textareas with live character count + colour-coded limit warnings
- [ ] Save button → calls `:curate_memory` Ash action with inline validation errors
- [ ] Episodic search bar → `recall_similar/1` → top-5 cards with content, type badge, timestamp
- [ ] Delete button per memory card
- [ ] Filter tabs: `All | :observation | :reflection | :user_fact | :synthetic`

**Exit Criteria:** Operator can read, search, edit, and delete agent memories without IEx.

### 7.3 — Reactor Workflow Log

- [ ] `HermesBeam.WorkflowLog` Ash Resource: `workflow_name`, `status`, `steps` (map), timestamps
- [ ] Telemetry `attach/4` on all Reactor steps in `AgentLoop`, `IntelligentRouter`, `SyntheticDataReactor`
- [ ] `HermesBeamWeb.Live.WorkflowLive` (`/dashboard/workflows`)
- [ ] Live table: sorted by `started_at`, paginated (25/page), status badge column
- [ ] Expandable rows: step-level horizontal bar chart (duration per step)
- [ ] Live counters: `Running: N | Completed today: N | Failed today: N`
- [ ] Retry button on failed rows — re-enqueues with original inputs

**Exit Criteria:** Running `Reactor.run(AgentLoop, ...)` in IEx causes a new row in the dashboard within 1 second.

### 7.4 — Skill Registry

- [ ] `HermesBeamWeb.Live.SkillsLive` (`/dashboard/skills`)
- [ ] Card grid: name, description, `execution_count`, `success_rate` badge
- [ ] Modal: syntax-highlighted code viewer for `elixir_code`
- [ ] Edit mode: operator amends code → "Recompile" calls `:refine_skill`
- [ ] Inline compilation error display
- [ ] Delete button → `Ash.destroy/1` + unloads BEAM module
- [ ] Sort: name / execution_count / success_rate / inserted_at
- [ ] Filter: All / High Success >90% / Needs Improvement <70% / Never Used

**Exit Criteria:** New skill appears in registry within 2 seconds of creation with `execution_count: 0`.

### 7.5 — Synthetic Data Monitor

- [ ] `HermesBeamWeb.Live.SyntheticLive` (`/dashboard/synthetic`)
- [ ] Bar chart: top 10 explored concepts by synthetic memory count
- [ ] Line chart: total episodic memory count over 7 days
- [ ] Manual trigger form: dispatch `SyntheticDataReactor` from browser
- [ ] Live feed: last 10 generated synthetic memories, auto-updating via PubSub

**Exit Criteria:** Dashboard reflects accurate memory count from Postgres and updates in real-time during generation.

---

## Phase 8 — Hardening and Production Readiness

> **Objective:** Make the system robust for 24/7 unattended operation.

- [ ] Automated Postgres backups (daily `pg_dump` to NAS or external drive)
- [ ] `mix release` configured for Hub and Worker node types
- [ ] `launchd` plist (macOS) for auto-start on Mac Minis
- [ ] `systemd` unit (Linux/Windows) for auto-start on Gaming PC
- [ ] Tailscale ACLs: restrict to EPMD port (4369) and Postgres (5432) only
- [ ] Erlang TLS distribution as secondary security layer over Tailscale
- [ ] Rate limiting on Ash AI tool-calling actions (prevent runaway LLM loops)
- [ ] `@moduledoc` on all public modules
- [ ] `CONTRIBUTING.md`

**Exit Criteria:** Full Hub reboot with zero data loss. Workers auto-reconnect within 30 seconds.

---

## Future Considerations

- **WASM Sandbox for Skills:** Evaluate running LLM-generated skill code inside an embedded WebAssembly runtime instead of directly on the BEAM for stronger isolation. Relevant authority: `wasmex` library (Elixir WASM bindings).
- **Federated Memory:** Explore syncing anonymised memory patterns across multiple Hermes BEAM instances.
- **MCP Server:** Expose agent capabilities as a Model Context Protocol server for IDE integrations (e.g. Cursor, Zed).
- **Ada/SPARK Core:** Explore re-implementing EXLA NIF bindings in Ada/SPARK for formal verification of the inference pipeline.
- **Headscale:** Replace Tailscale coordination server with self-hosted [Headscale](https://github.com/juanfont/headscale) for fully air-gapped operation.
