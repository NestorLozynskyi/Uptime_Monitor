defmodule UptimeMonitor.Repo.Migrations.CreateMonitoring do
  use Ecto.Migration

  def change do
    create table(:services) do
      add :name, :string, null: false
      add :url, :string, null: false, size: 2048
      add :interval_minutes, :integer, null: false
      add :public, :boolean, null: false, default: false
      add :status, :string, null: false, default: "pending"
      add :consecutive_failures, :integer, null: false, default: 0
      add :consecutive_successes, :integer, null: false, default: 0
      add :streak_started_at, :utc_datetime_usec
      add :last_checked_at, :utc_datetime_usec
      add :last_response_time_ms, :integer
      add :last_status_code, :integer
      add :last_error, :text
      add :next_check_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:services, :interval_minutes_allowed,
             check: "interval_minutes IN (1, 5, 15, 30, 60)"
           )

    create index(:services, [:next_check_at])
    create index(:services, [:public])

    create table(:checks) do
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :checked_at, :utc_datetime_usec, null: false
      add :result, :string, null: false
      add :status_code, :integer
      add :response_time_ms, :integer
      add :error, :text
      add :manual, :boolean, null: false, default: false
    end

    create index(:checks, [:service_id, :checked_at])
    create index(:checks, [:checked_at])

    # Hourly aggregates maintained on every check insert; used by 7d/30d
    # statistics so they never scan raw checks.
    create table(:check_rollups, primary_key: false) do
      add :service_id, references(:services, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :bucket_start, :utc_datetime, null: false, primary_key: true
      add :total_count, :integer, null: false, default: 0
      add :up_count, :integer, null: false, default: 0
      add :degraded_count, :integer, null: false, default: 0
      add :down_count, :integer, null: false, default: 0
      add :response_time_sum_ms, :bigint, null: false, default: 0
      add :response_time_count, :integer, null: false, default: 0
    end

    create index(:check_rollups, [:bucket_start])

    create table(:incidents) do
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :reason, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:incidents, [:service_id, :started_at])
    create index(:incidents, [:ended_at])

    create unique_index(:incidents, [:service_id],
             where: "ended_at IS NULL",
             name: :incidents_one_open_per_service_index
           )
  end
end
