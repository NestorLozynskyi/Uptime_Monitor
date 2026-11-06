defmodule UptimeMonitorWeb.SessionHTML do
  use UptimeMonitorWeb, :html

  @doc "Sign-in screen (design: login.html)."
  attr :email, :string, default: ""
  attr :errors, :map, default: %{}
  attr :error, :boolean, default: false

  def new(assigns) do
    ~H"""
    <Layouts.auth>
      <div class="panel auth-card">
        <div class="panel-body">
          <form
            class="form"
            action={~p"/login"}
            method="post"
            id="login-form"
            data-login-form
            novalidate
          >
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <div class="od-stack" style="--od-gap: 4px">
              <h1>Sign in</h1>
              <p class="muted small">Administrator access to your monitors.</p>
            </div>

            <div :if={@error} class="alert alert-error" role="alert" id="login-error">
              <.icon name="i-alert" />
              <div class="alert-body">
                <span class="alert-title">Incorrect email or password</span>
                <span class="muted">Check both fields and try again.</span>
              </div>
            </div>

            <div class="field">
              <label class="label" for="email">Email</label>
              <input
                class="input"
                id="email"
                name="admin[email]"
                type="email"
                autocomplete="username"
                required
                value={@email}
                autofocus={@email == ""}
                aria-invalid={@errors[:email] && "true"}
                aria-describedby={@errors[:email] && "email-error"}
              />
              <.field_error :if={@errors[:email]} id="email-error">{@errors[:email]}</.field_error>
            </div>
            <div class="field">
              <label class="label" for="password">Password</label>
              <input
                class="input"
                id="password"
                name="admin[password]"
                type="password"
                autocomplete="current-password"
                required
                autofocus={@email != ""}
                aria-invalid={@errors[:password] && "true"}
                aria-describedby={
                  (@errors[:password] && "password-error") || (@error && "login-error")
                }
              />
              <.field_error :if={@errors[:password]} id="password-error">
                {@errors[:password]}
              </.field_error>
            </div>

            <button class="btn btn-primary btn-block" type="submit" style="height:44px">
              <span class="btn-label when-idle">Sign in</span>
              <span class="btn-label when-busy">Signing in…</span>
            </button>
          </form>
        </div>
      </div>
    </Layouts.auth>
    """
  end
end
