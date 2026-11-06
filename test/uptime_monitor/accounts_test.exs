defmodule UptimeMonitor.AccountsTest do
  use UptimeMonitor.DataCase, async: true

  alias UptimeMonitor.Accounts
  alias UptimeMonitor.Accounts.Admin

  test "stores only a bcrypt hash of the password" do
    admin = admin_fixture(password: "super-secret-pass")
    stored = Repo.get!(Admin, admin.id)
    assert stored.password == nil
    assert "$2b$" <> _ = stored.hashed_password
    refute stored.hashed_password =~ "super-secret-pass"
  end

  test "authenticates by email and password" do
    admin = admin_fixture(email: "Ops@Example.com", password: "super-secret-pass")

    assert Accounts.get_admin_by_email_and_password("ops@example.com", "super-secret-pass").id ==
             admin.id

    refute Accounts.get_admin_by_email_and_password("ops@example.com", "wrong-password")
    refute Accounts.get_admin_by_email_and_password("other@example.com", "super-secret-pass")
    refute Accounts.get_admin_by_email_and_password(nil, nil)
  end

  test "validates email and password length" do
    assert {:error, cs} = Accounts.upsert_admin(%{email: "invalid", password: "short"})
    assert %{email: [_], password: ["should be at least 8 character(s)"]} = errors_on(cs)
  end

  test "there is exactly one administrator" do
    admin_fixture(email: "first@example.com")

    assert {:error, cs} =
             %Admin{}
             |> Admin.credentials_changeset(%{
               email: "second@example.com",
               password: "another-password"
             })
             |> Repo.insert()

    assert %{email: ["an administrator account already exists"]} = errors_on(cs)
  end

  test "upsert_admin replaces credentials and revokes sessions" do
    admin = admin_fixture()
    token = Accounts.generate_admin_session_token(admin)
    assert Accounts.get_admin_by_session_token(token)

    assert {:ok, updated} =
             Accounts.upsert_admin(%{email: "new@example.com", password: "new-password-123"})

    assert updated.id == admin.id
    refute Accounts.get_admin_by_session_token(token)
    assert Accounts.get_admin_by_email_and_password("new@example.com", "new-password-123")
  end

  test "ensure_admin creates only when none exists" do
    assert {:ok, :created} =
             Accounts.ensure_admin(%{email: "a@example.com", password: "password-123"})

    assert {:ok, :exists} =
             Accounts.ensure_admin(%{email: "b@example.com", password: "password-456"})

    assert Accounts.get_admin().email == "a@example.com"
  end

  test "session tokens can be verified and deleted" do
    admin = admin_fixture()
    token = Accounts.generate_admin_session_token(admin)
    assert Accounts.get_admin_by_session_token(token).id == admin.id
    :ok = Accounts.delete_admin_session_token(token)
    refute Accounts.get_admin_by_session_token(token)
    refute Accounts.get_admin_by_session_token("garbage")
  end

  test "expired session tokens are rejected" do
    admin = admin_fixture()
    token = Accounts.generate_admin_session_token(admin)

    Repo.update_all(Accounts.AdminToken,
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -15, :day)]
    )

    refute Accounts.get_admin_by_session_token(token)
  end
end
