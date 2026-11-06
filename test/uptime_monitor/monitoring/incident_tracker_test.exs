defmodule UptimeMonitor.Monitoring.IncidentTrackerTest do
  use ExUnit.Case, async: true

  alias UptimeMonitor.Monitoring.IncidentTracker

  defp run(results) do
    t0 = ~U[2026-01-01 00:00:00.000000Z]

    results
    |> Enum.with_index()
    |> Enum.map_reduce(%IncidentTracker{}, fn {r, i}, state ->
      {state, action} = IncidentTracker.step(state, r, DateTime.add(t0, i, :minute), "HTTP 500")
      {action, state}
    end)
  end

  test "opens after exactly 3 consecutive failures, from the first failure" do
    {actions, state} = run([:up, :down, :down, :down, :down])
    assert [:none, :none, :none, {:open, started, "HTTP 500"}, :none] = actions
    assert started == ~U[2026-01-01 00:01:00.000000Z]
    assert state.open_incident?
  end

  test "an interrupted failure series does not open an incident" do
    {actions, state} = run([:down, :down, :up, :down, :down, :degraded, :down, :down])
    assert Enum.all?(actions, &(&1 == :none))
    refute state.open_incident?
  end

  test "closes after 2 consecutive successes, at the first success" do
    {actions, state} = run([:down, :down, :down, :up, :up, :up])
    assert [_, _, {:open, _, _}, :none, {:close, ended}, :none] = actions
    assert ended == ~U[2026-01-01 00:03:00.000000Z]
    refute state.open_incident?
  end

  test "an interrupted recovery keeps the incident open" do
    {actions, state} = run([:down, :down, :down, :up, :down, :up, :down, :up, :up])
    assert [_, _, {:open, _, _}, :none, :none, :none, :none, :none, {:close, ended}] = actions
    assert ended == ~U[2026-01-01 00:07:00.000000Z]
    refute state.open_incident?
  end

  test "degraded counts as success" do
    {actions, _} = run([:down, :down, :down, :degraded, :degraded])
    assert {:close, _} = List.last(actions)
  end
end
