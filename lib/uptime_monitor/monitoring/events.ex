defmodule UptimeMonitor.Monitoring.Events do
  @moduledoc """
  Phoenix PubSub events for LiveViews.

  ## Admin topics

  Subscribe with `subscribe_admin/0` (all services) or `subscribe_service/1`.
  Messages have the shape `{:monitoring, event, payload}`:

    * `:service_created`, `:service_updated`, `:service_deleted` — `%{service: %Service{}}`
    * `:check_completed` — `%{service: %Service{}, check: %Check{}}`
    * `:status_changed` — `%{service: %Service{}, from: status, to: status}`
    * `:incident_opened`, `:incident_resolved` — `%{service: %Service{}, incident: %Incident{}}`

  ## Public topic

  Subscribe with `subscribe_public/0`. Only public services are broadcast,
  using the projections in `UptimeMonitor.Monitoring.PublicView`.
  Messages have the shape `{:public_status, event, payload}`:

    * `:service_updated` — `%{service: public_service}` (also sent when a service becomes public)
    * `:service_removed` — `%{service_id: id}` (deleted or made private)
    * `:check_completed` — `%{service: public_service, check: public_check}`
    * `:status_changed` — `%{service: public_service, from: status, to: status}`
    * `:incident_opened`, `:incident_resolved` — `%{service: public_service, incident: public_incident}`
  """
  alias Phoenix.PubSub
  alias UptimeMonitor.Monitoring.{PublicView, Service}

  @pubsub UptimeMonitor.PubSub
  @admin_topic "monitoring:services"
  @public_topic "monitoring:public"

  def admin_topic, do: @admin_topic
  def public_topic, do: @public_topic
  def service_topic(id), do: "monitoring:service:#{id}"

  def subscribe_admin, do: PubSub.subscribe(@pubsub, @admin_topic)
  def subscribe_service(id), do: PubSub.subscribe(@pubsub, service_topic(id))
  def subscribe_public, do: PubSub.subscribe(@pubsub, @public_topic)

  @doc "Broadcasts a service lifecycle change, handling public visibility transitions."
  def service_changed(event, %Service{} = service, previous \\ nil)
      when event in [:service_created, :service_updated, :service_deleted] do
    admin(service, event, %{service: service})

    was_public = previous != nil and previous.public
    is_public = event != :service_deleted and service.public

    cond do
      is_public ->
        public(:service_updated, %{service: PublicView.service(service)})

      was_public or (event == :service_deleted and service.public) ->
        public(:service_removed, %{service_id: service.id})

      true ->
        :ok
    end
  end

  def check_completed(service, check) do
    admin(service, :check_completed, %{service: service, check: check})

    if service.public do
      public(:check_completed, %{
        service: PublicView.service(service),
        check: PublicView.check(check)
      })
    end

    :ok
  end

  def status_changed(service, from, to) do
    admin(service, :status_changed, %{service: service, from: from, to: to})

    if service.public do
      public(:status_changed, %{service: PublicView.service(service), from: from, to: to})
    end

    :ok
  end

  def incident(event, service, incident) when event in [:incident_opened, :incident_resolved] do
    admin(service, event, %{service: service, incident: incident})

    if service.public do
      public(event, %{
        service: PublicView.service(service),
        incident: PublicView.incident(incident)
      })
    end

    :ok
  end

  defp admin(service, event, payload) do
    message = {:monitoring, event, payload}
    PubSub.broadcast(@pubsub, @admin_topic, message)
    PubSub.broadcast(@pubsub, service_topic(service.id), message)
  end

  defp public(event, payload) do
    PubSub.broadcast(@pubsub, @public_topic, {:public_status, event, payload})
  end
end
