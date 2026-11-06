defmodule UptimeMonitor.Monitoring.IncidentTracker do
  @moduledoc """
  Pure state machine deciding when incidents open and close.

    * an incident opens after 3 consecutive failed checks;
    * it resolves after 2 consecutive successful checks (degraded counts as success);
    * any opposite result interrupts the current series.
  """

  @failures_to_open 3
  @successes_to_close 2

  defstruct consecutive_failures: 0,
            consecutive_successes: 0,
            streak_started_at: nil,
            open_incident?: false

  @type t :: %__MODULE__{}
  @type action :: :none | {:open, DateTime.t(), String.t()} | {:close, DateTime.t()}

  def failures_to_open, do: @failures_to_open
  def successes_to_close, do: @successes_to_close

  @doc "Applies one check result. Returns `{new_state, action}`."
  @spec step(t(), :up | :degraded | :down, DateTime.t(), String.t() | nil) :: {t(), action()}
  def step(%__MODULE__{} = state, result, checked_at, error \\ nil) do
    if result in [:up, :degraded] do
      started =
        if state.consecutive_successes > 0, do: state.streak_started_at, else: checked_at

      state = %{
        state
        | consecutive_successes: state.consecutive_successes + 1,
          consecutive_failures: 0,
          streak_started_at: started
      }

      if state.open_incident? and state.consecutive_successes >= @successes_to_close do
        {%{state | open_incident?: false}, {:close, started}}
      else
        {state, :none}
      end
    else
      started = if state.consecutive_failures > 0, do: state.streak_started_at, else: checked_at

      state = %{
        state
        | consecutive_failures: state.consecutive_failures + 1,
          consecutive_successes: 0,
          streak_started_at: started
      }

      if not state.open_incident? and state.consecutive_failures >= @failures_to_open do
        {%{state | open_incident?: true}, {:open, started, error || "Check failed"}}
      else
        {state, :none}
      end
    end
  end
end
