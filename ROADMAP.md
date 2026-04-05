# Hermes BEAM — Roadmap

This roadmap follows **Documentation-Driven Development**: each phase is fully specified before implementation begins. The goal is to build a durable, self-improving AI agent network on BEAM that mirrors the Hermes Agent philosophy of persistent, closed-loop learning.

Status legend: `[ ]` = Not started · `[~]` = In progress · `[x]` = Complete

---

## Phase 0 — Foundation

> Objective: A working Elixir application that connects to Postgres and runs a basic LLM query locally.

- [ ] Create `mix.exs` with all dependencies: `ash`, `ash_postgres`, `ash_ai`, `reactor`, `bumblebee`, `nx`, `exla`, `libcluster`, `libcluster_postgres`
- [ ] Create `HermesBeam.Repo` (Ecto/AshPostgres)
- [ ] Create `HermesBeam.Domain` (Ash Domain)
- [ ] Configure `EXLA.Backend` as the global Nx backend in `config/config.exs`
- [ ] Verify Bumblebee loads a Phi-3 Mini model locally on a Mac Mini
- [ ] Verify EXLA compiles and runs on both MPS (Apple) and CUDA (Gaming PC)
- [ ] Write initial `priv/repo/migrations/` baseline migration

**Exit Criteria:** `mix run` boots on a single machine, runs a local Bumblebee text generation, and connects to Postgres.

---

## Phase 1 — Persistent Memory Layer

> Objective: Implement the Hermes-style bounded memory and the deeper semantic memory using pgvector.

- [ ] Install the `pgvector` Postgres extension on the Hub machine
- [ ] Create `HermesBeam.Memory.Scratchpad` Ash Resource
  - [ ] `memory_text` attribute (string, max 2,200 chars, validated by Ash)
  - [ ] `user_text` attribute (string, max 1,375 chars, validated by Ash)
  - [ ] `:curate_memory` update action exposed to the LLM via `AshAi`
  - [ ] `identities` constraint: one scratchpad per agent
- [ ] Create `HermesBeam.Memory` Ash Resource (episodic memory)
  - [ ] `content` attribute, auto-vectorized by `AshAi` embeddings
  - [ ] `content_vector` attribute (`Ash.Type.Vector`, 3072 dimensions)
  - [ ] `:recall_similar` read action via `AshAi.Query.VectorSearch`
  - [ ] `:store_memory` create action
  - [ ] `type` attribute: `:observation`, `:reflection`, `:user_fact`
- [ ] Write and run migrations for both resources
- [ ] Write tests for both resources confirming CRUD and vector search

**Exit Criteria:** An IEx session can store and semantically recall memories from Postgres.

---

## Phase 2 — Core Reasoning Loop (Reactor)

> Objective: Implement the autonomous Observe → Orient → Decide → Act agent cycle.

- [ ] Create `HermesBeam.Workflows.AgentLoop` Reactor
  - [ ] Step `:fetch_context` — queries `Memory.recall_similar/1` using user prompt
  - [ ] Step `:evaluate_and_decide` — calls LLM via `AshAi` with injected context, returns `{:ok, value, additional_steps}` for dynamic graph extension
  - [ ] Step `:reflect_and_learn` — summarizes interaction, stores reflection in `Memory`
  - [ ] Step `:curate_scratchpad` — calls `Scratchpad.curate_memory/1` with condensed context
- [ ] Create `HermesBeam.Workflows.IntelligentRouter` Reactor
  - [ ] Step `:determine_tier` — maps `:task_type` atom to `Nx.Serving` name
  - [ ] Step `:execute_inference` — calls `Nx.Serving.batched_run/2` with fallback on `:exit`
- [ ] Write integration tests for full agent loop on a single node

**Exit Criteria:** A full agent turn completes: receives prompt → recalls memory → generates response → stores reflection → updates scratchpad.

---

## Phase 3 — Autonomous Skill Creation

> Objective: Allow the agent to write, compile, and persist new Elixir skills.

- [ ] Create `HermesBeam.Skill` Ash Resource
  - [ ] `name`, `description`, `elixir_code` attributes
  - [ ] `execution_count` and `success_rate` tracked attributes
  - [ ] `:learn_skill` create action — triggers `CompileSkillModule` change
  - [ ] `:refine_skill` update action — re-triggers compilation on failure
- [ ] Create `HermesBeam.Changes.CompileSkillModule` Ash Change
  - [ ] Evaluate generated Elixir code via `Code.compile_string/1`
  - [ ] Register the module dynamically into the running BEAM VM
  - [ ] Return `{:error, reason}` on compilation failure to trigger `undo` in Reactor
- [ ] Expose `:learn_skill` and `:refine_skill` to the LLM as tools via `AshAi`
- [ ] Reactor `undo` step for skill failure: prompts LLM to reflect and rewrite
- [ ] Write sandbox tests for dynamically compiled skill modules

**Exit Criteria:** The agent is given a repetitive task, generates Elixir code for it, stores it in Postgres, compiles it live, and successfully uses it on the next invocation.

---

## Phase 4 — Multi-Tier Hardware Model Serving

> Objective: Load appropriate LLM weights onto each machine and distribute inference across the cluster.

- [ ] Create `HermesBeam.LLM.TierSupervisor` (dynamic supervisor)
  - [ ] Reads `NODE_ROLE` from environment
  - [ ] Dynamically generates child specs from the tier map in `config/runtime.exs`
- [ ] Create `HermesBeam.LLM.ModelWorker` (GenServer)
  - [ ] Loads model via `Bumblebee.load_model/2` with `:bf16` type
  - [ ] Loads tokenizer and generation config
  - [ ] Configures `max_new_tokens` per tier (Tier 1: 4096, Tier 2: 2048, Tier 3: 1024)
  - [ ] Starts `Nx.Serving.start_link/1` with `partitions: true` and a global name
- [ ] Validate cross-node `Nx.Serving.batched_run/2` routing works between a Mac Mini and the Gaming PC
- [ ] Verify CUDA compilation (`EXLA`) on Gaming PC
- [ ] Verify MPS compilation (`EXLA`) on Mac Minis
- [ ] Benchmark inter-node inference latency over Tailscale

**Exit Criteria:** A Reactor workflow on a Mac Mini successfully routes a Tier 1 task to the Gaming PC, waits, and returns the generated text.

---

## Phase 5 — Distributed Cluster (Tailscale + libcluster_postgres)

> Objective: Connect all nodes into a secure, fault-tolerant Erlang distribution mesh.

- [ ] Install Tailscale on the Gaming PC and all Mac Minis
- [ ] Disable Tailscale key expiry for all agent nodes
- [ ] Document the static Tailscale IPs for each machine
- [ ] Configure `libcluster_postgres` strategy in `config/config.exs`
- [ ] Create `bin/start_node.sh`
  - [ ] Dynamically reads Tailscale IP via `tailscale ip -4`
  - [ ] Passes IP as the Erlang node name (`--name agent@<tailscale_ip>`)
  - [ ] Sets Erlang magic cookie via `--cookie`
- [ ] Create `config/runtime.exs`
  - [ ] `NODE_TYPE=hub` → Postgres on `localhost`
  - [ ] `NODE_TYPE=worker` → Postgres on `HUB_IP` over Tailscale
- [ ] Update `HermesBeam.Application` to conditionally start Hub-only processes
- [ ] Test node discovery: worker connects to Hub, cluster forms automatically
- [ ] Test fault tolerance: unplug a Mac Mini, confirm Hub re-routes tasks

**Exit Criteria:** Three nodes (Hub + 2 Workers) form a cluster automatically. Killing a Worker node does not crash the Hub or remaining Workers.

---

## Phase 6 — Synthetic Data Generation

> Objective: Enable idle nodes to autonomously generate synthetic data to improve agent memory quality.

- [ ] Create `HermesBeam.Workflows.SyntheticDataReactor`
  - [ ] Input: `concept_to_explore` — a topic the agent wants to learn more about
  - [ ] Step `:generate_synthetic_scenarios` — routes to Tier 2 model, generates 3 realistic scenarios
  - [ ] Step `:process_and_store_scenarios` — stores outputs into `Memory` with type `:reflection`
- [ ] Create a scheduled Reactor task (Hub-only) that triggers `SyntheticDataReactor` for each domain the agent has low confidence in
- [ ] Measure vector recall quality before/after a synthetic data run

**Exit Criteria:** The agent autonomously fills gaps in its memory during idle time by generating synthetic scenarios and storing them as vectorized reflections.

---

## Phase 7 — Observability and Cluster Monitoring

> Objective: Provide visibility into the distributed agent's state, hardware usage, and memory evolution.

- [ ] Add `Phoenix` and `Phoenix.LiveView` to the Hub's supervision tree
- [ ] Build LiveView: **Cluster Health** — real-time view of all connected nodes, their `NODE_ROLE`, and current `Nx.Serving` load
- [ ] Build LiveView: **Agent Memory Explorer** — view and edit the current `Scratchpad` contents per agent
- [ ] Build LiveView: **Workflow Log** — display active and completed Reactor workflows with step-level timing
- [ ] Build LiveView: **Skill Registry** — list all dynamically compiled skills with execution counts and success rates
- [ ] Add Telemetry events to `Reactor` steps for real-time dashboard updates

**Exit Criteria:** Navigating to `http://hub-tailscale-ip:4000` shows the live cluster state and agent memory.

---

## Phase 8 — Hardening and Production Readiness

> Objective: Make the system robust for 24/7 unattended operation.

- [ ] Set up automated Postgres backups (daily pg_dump to local NAS or external drive)
- [ ] Configure `mix release` for all node types
- [ ] Create `launchd` plist (macOS) and `systemd` unit (Linux/Gaming PC) for auto-start on boot
- [ ] Configure Tailscale ACLs to restrict inter-node communication to only EPMD port (4369) and Postgres (5432)
- [ ] Add Erlang TLS distribution as an additional security layer over Tailscale
- [ ] Implement rate limiting on the Ash AI tool-calling actions to prevent runaway LLM loops
- [ ] Write a `CONTRIBUTING.md` and module-level `@moduledoc` documentation for all public modules

**Exit Criteria:** The system survives a full Hub reboot with zero data loss and Workers automatically reconnect.

---

## Future Considerations

- **WASM Sandbox for Skills:** Evaluate running LLM-generated skill code inside an embedded WebAssembly runtime instead of directly on the BEAM for stronger isolation.
- **Federated Memory:** Explore syncing anonymized memory patterns across multiple Hermes BEAM instances for collective intelligence.
- **Phoenix LiveView UI as MCP Server:** Expose agent capabilities as a Model Context Protocol server for IDE integrations.
- **Ada/SPARK Core:** Explore re-implementing the low-level NIF bindings between EXLA and the BEAM in Ada for formal verification of the inference pipeline.
