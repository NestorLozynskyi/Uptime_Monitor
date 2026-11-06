defmodule UptimeMonitor.Accounts.Admin do
  @moduledoc "The single administrator account."
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Inspect, except: [:password, :hashed_password]}
  schema "admins" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  @min_password_length 8

  @doc "Changeset used to create or update the admin credentials."
  def credentials_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> update_change(:email, &String.trim/1)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: @min_password_length, max: 72)
    |> unique_constraint(:email)
    |> unique_constraint(:email,
      name: :admins_single_row_index,
      message: "an administrator account already exists"
    )
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true} = changeset) do
    password = get_change(changeset, :password)

    changeset
    |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset

  @doc "Verifies the password, using a constant-time dummy check when no admin is given."
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and is_binary(password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
