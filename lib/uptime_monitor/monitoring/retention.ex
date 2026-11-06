defmodule UptimeMonitor.Monitoring.Retention do
  @moduledoc """
  Data retention: checks (and their hourly rollups) are kept for 30 days,
  resolved incidents for 90 days after they ended. Open incidents are never
  deleted. Deletes run in batches to keep transactions short.
  """
  import Ecto.Query

  alias UptimeMonitor.Repo
  alias UptimeMonitor.Monitoring.{Check, CheckRollup, Incident}

  @check_days 30
  @incident_days 90
  @batch 10_000

  def check_retention_days, do: @check_days
  def incident_retention_days, do: @incident_days

  @doc "Deletes expired data. Returns the number of deleted rows per table."
  def cleanup(now \\ DateTime.utc_now()) do
    check_cutoff = DateTime.add(now, -@check_days, :day)
    incident_cutoff = DateTime.add(now, -@incident_days, :day)

    rollup_cutoff =
      check_cutoff |> DateTime.truncate(:second) |> Map.merge(%{minute: 0, second: 0})

    %{
      checks: delete_in_batches(from(c in Check, where: c.checked_at < ^check_cutoff)),
      rollups:
        delete_in_batches_rollups(from(r in CheckRollup, where: r.bucket_start < ^rollup_cutoff)),
      incidents:
        delete_in_batches(
          from(i in Incident, where: not is_nil(i.ended_at) and i.ended_at < ^incident_cutoff)
        )
    }
  end

  defp delete_in_batches(query, acc \\ 0) do
    ids = from(q in query, select: q.id, limit: @batch)
    {deleted, _} = Repo.delete_all(from(t in query, where: t.id in subquery(ids)))
    if deleted == @batch, do: delete_in_batches(query, acc + deleted), else: acc + deleted
  end

  # Rollups are small (one row per service-hour), a single delete is enough.
  defp delete_in_batches_rollups(query) do
    {deleted, _} = Repo.delete_all(query)
    deleted
  end
end
