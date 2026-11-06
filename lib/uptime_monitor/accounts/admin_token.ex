defmodule UptimeMonitor.Accounts.AdminToken do
  @moduledoc "Session tokens for the administrator."
  use Ecto.Schema
  import Ecto.Query

  alias UptimeMonitor.Accounts.AdminToken

  @rand_size 32
  @session_validity_in_days 14

  schema "admin_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :admin, UptimeMonitor.Accounts.Admin

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def session_validity_in_days, do: @session_validity_in_days

  @doc "Builds a random session token. The raw token is stored in the signed session cookie."
  def build_session_token(admin) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %AdminToken{token: token, context: "session", admin_id: admin.id}}
  end

  @doc "Query returning the admin for a valid (non-expired) session token."
  def verify_session_token_query(token) do
    from t in AdminToken,
      join: a in assoc(t, :admin),
      where:
        t.token == ^token and t.context == "session" and
          t.inserted_at > ago(@session_validity_in_days, "day"),
      select: a
  end

  def by_token_and_context_query(token, context) do
    from AdminToken, where: [token: ^token, context: ^context]
  end

  def by_admin_query(admin_id) do
    from t in AdminToken, where: t.admin_id == ^admin_id
  end
end
