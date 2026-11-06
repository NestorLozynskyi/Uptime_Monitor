defmodule UptimeMonitorWeb.SessionController do
  use UptimeMonitorWeb, :controller

  alias UptimeMonitor.Accounts
  alias UptimeMonitorWeb.AdminAuth

  def new(conn, _params) do
    render(conn, :new, page_title: "Sign in")
  end

  def create(conn, %{"admin" => %{} = params}) do
    email = String.trim(params["email"] || "")
    password = params["password"] || ""

    errors =
      %{}
      |> put_error(:email, email_error(email))
      |> put_error(:password, if(password == "", do: "Enter your password."))

    cond do
      errors != %{} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:new, page_title: "Sign in", email: email, errors: errors)

      admin = Accounts.get_admin_by_email_and_password(email, password) ->
        AdminAuth.log_in_admin(conn, admin)

      true ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, page_title: "Sign in", email: email, error: true)
    end
  end

  def create(conn, _params), do: create(conn, %{"admin" => %{}})

  def delete(conn, _params), do: AdminAuth.log_out_admin(conn)

  defp email_error(""), do: "Enter your email."

  defp email_error(email),
    do: if(email =~ ~r/^\S+@\S+\.\S+$/, do: nil, else: "Enter a valid email address.")

  defp put_error(errors, _field, nil), do: errors
  defp put_error(errors, field, message), do: Map.put(errors, field, message)
end
