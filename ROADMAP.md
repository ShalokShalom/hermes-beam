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

## Phase 7 — Phoenix LiveView Dashboard

> Objective: Provide a real-time, browser-based command centre on the Hub node to monitor every dimension of the distributed agent network — cluster health, agent memory, workflow execution, and skill evolution.

### 7.0 — Project Setup

- [ ] Add `phoenix`, `phoenix_live_view`, `phoenix_html`, `phoenix_ecto`, `esbuild`, `tailwind` to `mix.exs`
- [ ] Add `HermesBeamWeb.Endpoint` and `HermesBeamWeb.Telemetry` as Hub-only children in `HermesBeam.Application`
- [ ] Configure `config/dev.exs` and `config/prod.exs` with Endpoint settings (port `4000`, `LiveView` signing salt)
- [ ] Create `lib/hermes_beam_web/` directory with `router.ex`, `endpoint.ex`, `telemetry.ex`
- [ ] Set up `assets/` with Tailwind CSS for component styling
- [ ] Add a root layout `lib/hermes_beam_web/components/layouts/root.html.heex` with navbar links to all dashboards

**Exit Criteria:** Navigating to `http://hub-tailscale-ip:4000` returns a styled HTML page with navigation links.

---

### 7.1 — Cluster Health Dashboard

> Real-time view of every Erlang node, its hardware tier, active model servings, and GPU memory pressure.

**Data sources:**
- `Node.list/0` — lists all connected Erlang nodes
- `:rpc.call(node, System, :schedulers_online, [])` — remote CPU core count
- `:rpc.call(node, Application, :fetch_env!, [:hermes_beam, :hardware_topology], [])` — remote `NODE_ROLE`
- Custom `HermesBeam.Telemetry.NodeMetrics` GenServer — polls EXLA memory stats per node

**LiveView components:**
- [ ] Create `HermesBeamWeb.Live.ClusterLive` (`/dashboard/cluster`)
- [ ] Node card grid showing per-node: name, Tailscale IP, `NODE_ROLE`, status (`:online` / `:degraded`)
- [ ] `Nx.Serving` table per node: tier name, active batch count, `max_new_tokens`, model repo
- [ ] Live sparkline per node showing inference requests per minute (via `:telemetry` events)
- [ ] Red badge auto-appears on a node card if it drops from `Node.list/0`
- [ ] Create `HermesBeam.Telemetry.NodeMetrics` GenServer that broadcasts `Phoenix.PubSub` events every 2 seconds

**Exit Criteria:** When a Worker Mac Mini is unplugged, its card turns red within 5 seconds with no page refresh.

---

### 7.2 — Agent Memory Explorer

> Browse, search, and manually edit the bounded `Scratchpad` and explore the full episodic `Memory` vector store.

**Data sources:**
- `HermesBeam.Memory.Scratchpad` Ash Resource (direct DB read)
- `HermesBeam.Memory` Ash Resource (pgvector nearest-neighbour search)

**LiveView components:**
- [ ] Create `HermesBeamWeb.Live.MemoryLive` (`/dashboard/memory`)
- [ ] Scratchpad panel: two side-by-side `<textarea>` elements for `memory_text` and `user_text` with live character count and colour-coded limit warnings (green → yellow → red as limit approaches)
- [ ] "Save" button calls `Ash.update(scratchpad, :curate_memory, ...)` directly, with inline validation error display
- [ ] Episodic memory search bar: user types a query, LiveView calls `Memory.recall_similar/1` and renders the top-5 results as cards showing content, type badge, and timestamp
- [ ] Each memory card has a "Delete" action calling `Ash.destroy/1`
- [ ] Memory type filter tabs: `All | :observation | :reflection | :user_fact`

**Exit Criteria:** An operator can read, search, edit, and delete agent memories directly from the browser without touching IEx.

---

### 7.3 — Reactor Workflow Log

> A live feed of every Reactor workflow execution — running, completed, and failed — with step-level timing and error details.

**Data sources:**
- Custom `:telemetry` events attached to `Reactor` steps
- `HermesBeam.WorkflowLog` Ash Resource (new — stores workflow execution records in Postgres)

**New Ash Resource:**
- [ ] Create `HermesBeam.WorkflowLog` resource
  - [ ] `workflow_name` (string), `status` (atom: `:running`, `:completed`, `:failed`)
  - [ ] `steps` (map) — step name → `%{started_at, finished_at, status, error}`
  - [ ] `started_at`, `finished_at` timestamps
  - [ ] `:create`, `:update_step`, `:complete`, `:fail` actions

**LiveView components:**
- [ ] Create `HermesBeamWeb.Live.WorkflowLive` (`/dashboard/workflows`)
- [ ] Live table of recent workflow runs, sorted by `started_at` descending, paginated (25 per page)
- [ ] Status badge column: green `completed`, blue `running`, red `failed`
- [ ] Row expandable: clicking a row reveals step-level timeline with duration per step rendered as a horizontal bar chart
- [ ] Live counter at the top: `Running: N | Completed today: N | Failed today: N`
- [ ] "Retry" button on failed workflow rows — re-enqueues the Reactor workflow with original inputs
- [ ] Add `:telemetry` `attach/4` calls to `AgentLoop`, `IntelligentRouter`, `SyntheticDataReactor` to emit step start/stop events

**Exit Criteria:** Running `Reactor.run(HermesBeam.Workflows.AgentLoop, ...)` in IEx causes a new row to appear live in the dashboard within 1 second.

---

### 7.4 — Skill Registry

> A living catalogue of every dynamically compiled Elixir skill the agent has learned, with usage stats and the ability to view, edit, and delete skills.

**Data sources:**
- `HermesBeam.Skill` Ash Resource

**LiveView components:**
- [ ] Create `HermesBeamWeb.Live.SkillsLive` (`/dashboard/skills`)
- [ ] Card grid of all skills: name, description, `execution_count`, `success_rate` as a percentage badge
- [ ] Clicking a card opens a modal with a syntax-highlighted read-only code viewer for `elixir_code`
- [ ] "Edit" mode in the modal: operator can manually amend the code and click "Recompile" which calls `:refine_skill` Ash Action
- [ ] Inline compilation error display if `Code.compile_string/1` fails
- [ ] "Delete" button in modal triggers `Ash.destroy/1` and unloads the BEAM module
- [ ] Sort controls: by `name`, `execution_count`, `success_rate`, `inserted_at`
- [ ] Filter: `All | High Success (>90%) | Needs Improvement (<70%) | Never Used`

**Exit Criteria:** After the agent autonomously creates a new skill (Phase 3), the skill appears in the registry within 2 seconds with `execution_count: 0`.

---

### 7.5 — Synthetic Data Monitor

> Track the agent's self-improvement progress: which concepts have been explored, how many synthetic memories were generated, and how they affected recall quality.

**LiveView components:**
- [ ] Create `HermesBeamWeb.Live.SyntheticLive` (`/dashboard/synthetic`)
- [ ] Bar chart: top 10 most explored concepts by synthetic memory count
- [ ] Memory growth chart: line graph of total episodic `Memory` count over the past 7 days
- [ ] "Trigger Run" form: operator inputs a concept and manually dispatches a `SyntheticDataReactor` workflow
- [ ] Live feed of the most recently generated synthetic memories (last 10), auto-updating via PubSub

**Exit Criteria:** The dashboard accurately reflects the total memory count from Postgres and updates in real-time as synthetic data is generated.

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
