defmodule Mix.Tasks.Uptime.Admin do
  @shortdoc "Creates the administrator or replaces its credentials"
  @moduledoc """
  Creates the single administrator account, or replaces the email and password
  of the existing one (all existing sessions are revoked).

      mix uptime.admin admin@example.com

  The password is read from the `ADMIN_PASSWORD` environment variable or, when
  it is not set, prompted for interactively. It is stored only as a bcrypt hash.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run([email]) do
    password =
      case System.get_env("ADMIN_PASSWORD") do
        nil -> Mix.shell().prompt("Password:") |> String.trim()
        value -> value
      end

    case UptimeMonitor.Accounts.upsert_admin(%{email: email, password: password}) do
      {:ok, admin} ->
        Mix.shell().info("Administrator #{admin.email} saved.")

      {:error, changeset} ->
        Mix.raise("Could not save administrator: #{inspect(errors(changeset))}")
    end
  end

  def run(_), do: Mix.raise("Usage: mix uptime.admin EMAIL")

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
