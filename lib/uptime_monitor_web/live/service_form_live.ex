defmodule UptimeMonitorWeb.ServiceFormLive do
  @moduledoc """
  Add / Edit service. Fields are validated when they lose focus and on
  submit; the URL is checked on the server against the SSRF rules (the
  server is authoritative). On submit an error summary lists every problem.
  """
  use UptimeMonitorWeb, :live_view

  alias UptimeMonitor.Monitoring
  alias UptimeMonitor.Monitoring.Service

  @blocked_message "This address is not allowed. Private, local and internal network addresses can’t be monitored."

  @impl true
  def mount(params, _session, socket) do
    case load_service(socket.assigns.live_action, params) do
      nil ->
        {:ok, socket |> put_flash(:error, "Service not found.") |> push_navigate(to: ~p"/admin")}

      service ->
        title = if socket.assigns.live_action == :new, do: "Add service", else: "Edit service"

        {:ok,
         socket
         |> assign(page_title: title, service: service, submitted: false)
         |> assign_form(Monitoring.change_service(service))}
    end
  end

  defp load_service(:new, _params), do: %Service{interval_minutes: 5, public: false}

  defp load_service(:edit, %{"id" => id}) do
    case Integer.parse(id) do
      {id, ""} -> Monitoring.get_service(id)
      _ -> nil
    end
  end

  defp assign_form(socket, changeset) do
    errors = if changeset.action, do: messages(changeset), else: %{}
    assign(socket, form: to_form(changeset, as: "service"), errors: errors)
  end

  @impl true
  def handle_event("validate", %{"service" => params}, socket) do
    changeset =
      socket.assigns.service
      |> Monitoring.change_service(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"service" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Monitoring.create_service(params)
        :edit -> Monitoring.update_service(socket.assigns.service, params)
      end

    case result do
      {:ok, service} ->
        to =
          if socket.assigns.live_action == :new,
            do: ~p"/admin",
            else: ~p"/admin/services/#{service}"

        {:noreply, push_navigate(socket, to: to)}

      {:error, changeset} ->
        {:noreply, socket |> assign(submitted: true) |> assign_form(changeset)}
    end
  end

  # Field error messages in the product's wording.
  defp messages(changeset) do
    url = Ecto.Changeset.get_field(changeset, :url) || ""

    Map.new(changeset.errors, fn {field, {msg, opts}} ->
      {field, message(field, msg, opts, url)}
    end)
  end

  defp message(:name, _msg, opts, _url) do
    if opts[:validation] == :required,
      do: "Enter a name for this service.",
      else: "Use 100 characters or fewer."
  end

  defp message(:url, msg, opts, url) do
    cond do
      opts[:validation] == :required ->
        "Enter the address to monitor."

      opts[:validation] == :length ->
        "Use 2048 characters or fewer."

      opts[:kind] == :blocked ->
        @blocked_message

      opts[:kind] == :dns ->
        "We couldn’t find this address. Check the host name and try again."

      msg =~ "credentials" ->
        "Remove the user name and password from the address."

      msg =~ "only http" and url =~ "://" ->
        "Only http:// and https:// addresses can be monitored."

      true ->
        "Enter a full address that starts with http:// or https://"
    end
  end

  defp message(:interval_minutes, _msg, _opts, _url), do: "Choose how often to check."
  defp message(_field, msg, _opts, _url), do: msg

  # Errors are shown under a field once it has been used, and for all fields after submit.
  defp field_error(assigns, field) do
    form_field = assigns.form[field]

    if assigns.submitted or Phoenix.Component.used_input?(form_field),
      do: assigns.errors[field]
  end

  @field_ids [name: "svc-name", url: "svc-url", interval_minutes: "svc-interval-5"]

  defp summary(errors) do
    for {field, id} <- @field_ids, msg = errors[field], do: {id, msg}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        name_error: field_error(assigns, :name),
        url_error: field_error(assigns, :url),
        interval_error: field_error(assigns, :interval_minutes),
        summary: if(assigns.submitted, do: summary(assigns.errors), else: []),
        interval: to_string(assigns.form[:interval_minutes].value),
        public: assigns.form[:public].value in [true, "true"]
      )

    ~H"""
    <Layouts.admin>
      <.link :if={@live_action == :new} class="back" navigate={~p"/admin"} style="margin-bottom: 12px">
        <.icon name="i-back" class="i i-sm" />Dashboard
      </.link>
      <.link
        :if={@live_action == :edit}
        class="back"
        navigate={~p"/admin/services/#{@service}"}
        style="margin-bottom: 12px"
      >
        <.icon name="i-back" class="i i-sm" />{@service.name}
      </.link>

      <div class="page-head">
        <div class="page-head-title">
          <h1>{if @live_action == :new, do: "Add service", else: "Edit service"}</h1>
        </div>
      </div>

      <section class="panel form-card">
        <div class="panel-body">
          <.form
            for={@form}
            id="service-form"
            class="form"
            phx-change="validate"
            phx-submit="save"
            novalidate
          >
            <div
              :if={@summary != []}
              class="alert alert-error"
              role="alert"
              tabindex="-1"
              id="error-summary"
              phx-mounted={Phoenix.LiveView.JS.focus()}
            >
              <.icon name="i-alert" />
              <div class="alert-body">
                <span class="alert-title">
                  {if length(@summary) == 1,
                    do: "Fix 1 problem to continue",
                    else: "Fix #{length(@summary)} problems to continue"}
                </span>
                <ul>
                  <li :for={{id, msg} <- @summary}><a href={"#" <> id}>{msg}</a></li>
                </ul>
              </div>
            </div>

            <p class="small muted"><span class="req" aria-hidden="true">*</span> Required</p>

            <div class="field">
              <label class="label" for="svc-name">Name<span class="req" aria-hidden="true">*</span></label>
              <input
                class="input"
                id="svc-name"
                name={@form[:name].name}
                value={@form[:name].value}
                type="text"
                required
                autocomplete="off"
                maxlength="100"
                phx-debounce="blur"
                aria-invalid={@name_error && "true"}
                aria-describedby={
                  Enum.join(
                    ["svc-name-help", @name_error && "svc-name-error"] |> Enum.filter(& &1),
                    " "
                  )
                }
              />
              <span class="help" id="svc-name-help">
                Shown on the dashboard and, if public, on the status page.
              </span>
              <.field_error :if={@name_error} id="svc-name-error">{@name_error}</.field_error>
            </div>

            <div class="field">
              <label class="label" for="svc-url">URL<span class="req" aria-hidden="true">*</span></label>
              <input
                class="input mono"
                id="svc-url"
                name={@form[:url].name}
                value={@form[:url].value}
                type="url"
                inputmode="url"
                required
                autocomplete="off"
                spellcheck="false"
                placeholder="https://example.com/health"
                phx-debounce="blur"
                aria-invalid={@url_error && "true"}
                aria-describedby={
                  Enum.join(["svc-url-help", @url_error && "svc-url-error"] |> Enum.filter(& &1), " ")
                }
              />
              <span class="help" id="svc-url-help">
                A public http:// or https:// address. Private, local and internal network addresses aren’t allowed.
              </span>
              <.field_error :if={@url_error} id="svc-url-error">{@url_error}</.field_error>
            </div>

            <fieldset class="field">
              <legend class="label">Check every<span class="req" aria-hidden="true">*</span></legend>
              <div class="choices">
                <label :for={m <- Service.intervals()} class="choice">
                  <input
                    type="radio"
                    id={"svc-interval-#{m}"}
                    name={@form[:interval_minutes].name}
                    value={m}
                    checked={@interval == to_string(m)}
                  /><span>{m} min</span>
                </label>
              </div>
              <span class="help">
                A check is Down on HTTP 4xx/5xx, no response within 10 s, or a DNS/connection error. Degraded when a successful response takes longer than 3 s.
              </span>
              <.field_error :if={@interval_error} id="svc-interval-error">
                {@interval_error}
              </.field_error>
            </fieldset>

            <label class="switch-row" for="svc-public">
              <span class="od-field od-fill">
                <span class="label">Show on public status page</span>
                <span class="help">
                  Visitors see the name, current status, uptime and availability history. The URL stays hidden.
                </span>
              </span>
              <input type="hidden" name={@form[:public].name} value="false" />
              <input
                class="switch od-fixed"
                id="svc-public"
                name={@form[:public].name}
                type="checkbox"
                role="switch"
                value="true"
                checked={@public}
              />
            </label>

            <div class="form-actions">
              <button class="btn btn-primary" type="submit" style="height:44px" id="save-service">
                <.icon name={if @live_action == :new, do: "i-plus", else: "i-check"} class="i i-sm" />
                <span class="btn-label when-idle">
                  {if @live_action == :new, do: "Add service", else: "Save changes"}
                </span>
                <span class="btn-label when-busy">Saving…</span>
              </button>
              <.link
                class="btn btn-secondary"
                navigate={
                  if @live_action == :new, do: ~p"/admin", else: ~p"/admin/services/#{@service}"
                }
                style="height:44px"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      </section>
    </Layouts.admin>
    """
  end
end
