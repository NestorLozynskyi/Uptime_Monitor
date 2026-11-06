defmodule UptimeMonitor.Repo.Migrations.CreateAdmins do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:admins) do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admins, [:email])
    # The application has exactly one administrator account.
    create unique_index(:admins, ["(true)"], name: :admins_single_row_index)

    create table(:admin_tokens) do
      add :admin_id, references(:admins, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:admin_tokens, [:admin_id])
    create unique_index(:admin_tokens, [:context, :token])
  end
end
