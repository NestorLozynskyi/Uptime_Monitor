defmodule UptimeMonitor.Accounts do
  @moduledoc """
  Authentication for the single administrator account.

  There is no registration flow. The admin is created or updated with
  `mix uptime.admin` (development) or from `ADMIN_EMAIL` / `ADMIN_PASSWORD`
  on release start (`UptimeMonitor.Release.setup/0`).
  """
  import Ecto.Query

  alias UptimeMonitor.Repo
  alias UptimeMonitor.Accounts.{Admin, AdminToken}

  @doc "Returns the administrator, or nil when none has been created."
  def get_admin, do: Repo.one(from a in Admin, limit: 1)

  @doc "Returns the admin when email and password match, otherwise nil."
  def get_admin_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    admin = Repo.get_by(Admin, email: String.trim(email))
    if Admin.valid_password?(admin, password), do: admin
  end

  def get_admin_by_email_and_password(_, _), do: nil

  @doc """
  Creates the administrator or replaces the credentials of the existing one.
  Existing sessions are revoked when credentials change.
  """
  def upsert_admin(attrs) do
    case get_admin() do
      nil ->
        %Admin{} |> Admin.credentials_changeset(attrs) |> Repo.insert()

      admin ->
        Repo.transaction(fn ->
          case admin |> Admin.credentials_changeset(attrs) |> Repo.update() do
            {:ok, admin} ->
              Repo.delete_all(AdminToken.by_admin_query(admin.id))
              admin

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  @doc """
  Creates the administrator from the given credentials only when no admin exists.
  Returns `{:ok, :created}`, `{:ok, :exists}` or `{:error, changeset}`.
  """
  def ensure_admin(attrs) do
    if get_admin() do
      {:ok, :exists}
    else
      case %Admin{} |> Admin.credentials_changeset(attrs) |> Repo.insert() do
        {:ok, _} -> {:ok, :created}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  ## Sessions

  def generate_admin_session_token(%Admin{} = admin) do
    {token, admin_token} = AdminToken.build_session_token(admin)
    Repo.insert!(admin_token)
    token
  end

  def get_admin_by_session_token(token) when is_binary(token) do
    Repo.one(AdminToken.verify_session_token_query(token))
  end

  def get_admin_by_session_token(_), do: nil

  def delete_admin_session_token(token) when is_binary(token) do
    Repo.delete_all(AdminToken.by_token_and_context_query(token, "session"))
    :ok
  end

  def delete_admin_session_token(_), do: :ok
end
