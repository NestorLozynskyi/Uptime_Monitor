defmodule UptimeMonitor.Release do
  @moduledoc """
  Release tasks, run with `bin/uptime_monitor eval "UptimeMonitor.Release.setup()"`.

  `setup/0` runs migrations, creates the administrator from `ADMIN_EMAIL` /
  `ADMIN_PASSWORD` if none exists yet, and seeds demo data when
  `DEMO_SEED=true` (target URL from `DEMO_TARGET_URL`).
  """
  require Logger

  @app :uptime_monitor

  def setup do
    migrate()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(UptimeMonitor.Repo, fn _repo ->
        ensure_admin()
        maybe_seed_demo()
      end)

    :ok
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp ensure_admin do
    email = System.get_env("ADMIN_EMAIL")
    password = System.get_env("ADMIN_PASSWORD")

    if email && password do
      case UptimeMonitor.Accounts.ensure_admin(%{email: email, password: password}) do
        {:ok, :created} ->
          Logger.info("Administrator #{email} created")

        {:ok, :exists} ->
          Logger.info("Administrator already exists, ADMIN_* ignored")

        {:error, changeset} ->
          raise "Invalid ADMIN_EMAIL/ADMIN_PASSWORD: #{inspect(changeset.errors)}"
      end
    else
      Logger.info("ADMIN_EMAIL/ADMIN_PASSWORD not set, administrator not created")
    end
  end

  defp maybe_seed_demo do
    if System.get_env("DEMO_SEED") in ~w(true 1) do
      # Service creation broadcasts PubSub events; start a local PubSub so the
      # seeder can run outside the application supervision tree.
      {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

      {:ok, _} =
        Supervisor.start_link([{Phoenix.PubSub, name: UptimeMonitor.PubSub}],
          strategy: :one_for_one
        )

      url = System.get_env("DEMO_TARGET_URL", "http://demo-target:4100")
      UptimeMonitor.Demo.Seeder.run(url)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
