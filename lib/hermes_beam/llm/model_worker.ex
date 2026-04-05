defmodule HermesBeam.LLM.ModelWorker do
  @moduledoc """
  Loads a single Bumblebee model into EXLA (CUDA or Metal) and starts a
  distributed `Nx.Serving` under the tier's atom name.

  Once started, any node in the Erlang cluster can call:

      Nx.Serving.batched_run(:tier_1_reasoning, prompt)

  If the calling node does not host that serving, the BEAM VM will
  automatically forward the request to the node that does — entirely
  transparently and encrypted over the Tailscale tunnel.
  """
  use GenServer
  require Logger

  @max_tokens_per_tier %{
    tier_1_reasoning: 4096,
    tier_2_general: 2048,
    tier_3_docs: 1024
  }

  def start_link({tier_name, hf_repo}) do
    GenServer.start_link(__MODULE__, {tier_name, hf_repo}, name: tier_name)
  end

  @impl true
  def init({tier_name, hf_repo}) do
    # Load the model outside of init to avoid blocking the supervisor.
    # This sends the node an async message to kick off the (slow) model load.
    send(self(), {:load_model, tier_name, hf_repo})
    {:ok, %{tier: tier_name, repo: hf_repo, serving_pid: nil}}
  end

  @impl true
  def handle_info({:load_model, tier_name, hf_repo}, state) do
    Logger.info("[ModelWorker] Loading #{hf_repo} for tier #{tier_name}...")

    max_tokens = Map.get(@max_tokens_per_tier, tier_name, 2048)

    {:ok, model_info}        = Bumblebee.load_model({:hf, hf_repo}, type: :bf16, backend: EXLA.Backend)
    {:ok, tokenizer}         = Bumblebee.load_tokenizer({:hf, hf_repo})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, hf_repo})

    generation_config =
      Bumblebee.configure(generation_config,
        max_new_tokens: max_tokens,
        strategy: %{type: :multinomial_sampling, top_p: 0.9}
      )

    serving =
      Bumblebee.Text.generation(model_info, tokenizer, generation_config,
        compile: [batch_size: 4, sequence_length: max_tokens],
        defn_options: [compiler: EXLA]
      )

    {:ok, pid} =
      Nx.Serving.start_link(
        serving: serving,
        name: tier_name,
        batch_timeout: 100,
        partitions: true
      )

    Logger.info("[ModelWorker] #{tier_name} ready (pid: #{inspect(pid)})")
    {:noreply, %{state | serving_pid: pid}}
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Generate text from the given prompt using the serving registered under
  `tier_name`. Routes automatically to the correct cluster node.
  """
  @spec generate(atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate(tier_name, prompt) do
    try do
      %{results: [%{text: text} | _]} = Nx.Serving.batched_run(tier_name, prompt)
      {:ok, text}
    catch
      :exit, reason -> {:error, reason}
    end
  end
end
