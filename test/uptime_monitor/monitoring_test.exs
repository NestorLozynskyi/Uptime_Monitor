defmodule UptimeMonitor.MonitoringTest do
  use UptimeMonitor.DataCase, async: true

  alias UptimeMonitor.Monitoring
  alias UptimeMonitor.Monitoring.{Check, CheckRollup, Events, Incident, Service}
  alias UptimeMonitor.Monitoring.Resolver.Stub
  alias UptimeMonitor.TargetServer

  describe "service CRUD" do
    test "creates a service with valid attributes" do
      assert {:ok, %Service{} = s} =
               Monitoring.create_service(%{
                 name: " API ",
                 url: TargetServer.url("/ok"),
                 interval_minutes: 5,
                 public: true
               })

      assert s.name == "API"
      assert s.status == :pending
      assert s.public
      assert s.next_check_at
    end

    test "validates name, interval and URL" do
      assert {:error, cs} = Monitoring.create_service(%{name: "", url: "", interval_minutes: 2})
      errors = errors_on(cs)
      assert errors.name == ["can't be blank"]
      assert errors.url == ["can't be blank"]
      assert errors.interval_minutes == ["must be one of 1, 5, 15, 30 or 60 minutes"]

      for i <- [1, 5, 15, 30, 60] do
        assert Monitoring.change_service(%Service{}, %{
                 name: "x",
                 url: "http://93.184.216.34",
                 interval_minutes: i
               }).valid?
      end
    end

    test "rejects forbidden URLs with a clear validation error" do
      assert {:error, cs} =
               Monitoring.create_service(%{
                 name: "x",
                 url: "http://169.254.169.254/",
                 interval_minutes: 1
               })

      assert [message] = errors_on(cs).url
      assert message =~ "169.254.169.254"
      assert message =~ "not allowed"

      Stub.put("private-host.crud.test", [{10, 0, 0, 7}])

      assert {:error, cs} =
               Monitoring.create_service(%{
                 name: "x",
                 url: "http://private-host.crud.test/",
                 interval_minutes: 1
               })

      assert [message] = errors_on(cs).url
      assert message =~ "10.0.0.7"
      assert {_, kind: :blocked} = cs.errors[:url]

      assert {:error, cs} =
               Monitoring.create_service(%{
                 name: "x",
                 url: "ftp://example.com",
                 interval_minutes: 1
               })

      assert errors_on(cs).url == ["only http:// and https:// URLs are allowed"]
      assert {_, kind: :invalid} = cs.errors[:url]
    end

    test "updates and deletes a service with its data" do
      service = service_fixture(next_check_at: DateTime.add(DateTime.utc_now(), 3600, :second))
      check_fixture(service, :up, DateTime.utc_now())
      incident_fixture(service, DateTime.utc_now())

      assert {:ok, updated} =
               Monitoring.update_service(service, %{name: "Renamed", interval_minutes: 5})

      assert updated.name == "Renamed"
      # Shortening the interval pulls the next check forward.
      assert DateTime.diff(updated.next_check_at, DateTime.utc_now()) <= 300

      assert {:ok, _} = Monitoring.delete_service(updated)
      refute Repo.get(Service, service.id)
      assert Repo.aggregate(from(c in Check, where: c.service_id == ^service.id), :count) == 0
      assert Repo.aggregate(from(i in Incident, where: i.service_id == ^service.id), :count) == 0
    end
  end

  describe "record_check/3 and incidents" do
    setup do
      %{service: service_fixture()}
    end

    defp record(service, results) do
      t0 = DateTime.add(DateTime.utc_now(), -length(results), :minute)

      for {r, i} <- Enum.with_index(results) do
        {:ok, %{service: s}} =
          Monitoring.record_check(service.id, result(r, DateTime.add(t0, i, :minute)))

        s
      end
      |> List.last()
    end

    test "stores the check, updates status and rollup", %{service: service} do
      at = DateTime.utc_now()

      assert {:ok, %{service: s, check: check}} =
               Monitoring.record_check(service.id, result(:degraded, at))

      assert s.status == :degraded
      assert s.last_response_time_ms == 3500
      assert check.result == :degraded

      assert [%CheckRollup{total_count: 1, degraded_count: 1, response_time_sum_ms: 3500}] =
               Repo.all(CheckRollup)
    end

    test "opens an incident after 3 consecutive failures", %{service: service} do
      s = record(service, [:up, :down, :down])
      assert s.status == :down
      refute Monitoring.get_open_incident(service.id)

      record(service, [:down])
      incident = Monitoring.get_open_incident(service.id)
      assert incident.reason == "HTTP 503"
      assert incident.ended_at == nil
    end

    test "incident start is the time of the first failure", %{service: service} do
      t0 = ~U[2026-11-01 10:00:00.000000Z]

      for i <- 0..2 do
        Monitoring.record_check(
          service.id,
          result(:down, DateTime.add(t0, i, :minute), error: "Timed out after 10 s")
        )
      end

      assert %Incident{started_at: ^t0, reason: "Timed out after 10 s"} =
               Monitoring.get_open_incident(service.id)
    end

    test "an interrupted failure series does not open an incident", %{service: service} do
      record(service, [:down, :down, :up, :down, :down, :degraded, :down, :down])
      assert Repo.aggregate(Incident, :count) == 0
    end

    test "closes after 2 consecutive successes, interrupted recovery keeps it open", %{
      service: service
    } do
      record(service, [:down, :down, :down, :up, :down, :up])
      assert Monitoring.get_open_incident(service.id)

      record(service, [:degraded])
      refute Monitoring.get_open_incident(service.id)

      assert [%Incident{ended_at: ended}] = Repo.all(Incident)
      assert ended
    end

    test "a failure series after a resolved incident opens a new one", %{service: service} do
      record(service, [:down, :down, :down, :up, :up, :down, :down, :down])
      assert Repo.aggregate(Incident, :count) == 2
      assert Monitoring.get_open_incident(service.id)
    end

    test "returns not_found for deleted services" do
      assert {:error, :not_found} = Monitoring.record_check(-1, result(:up))
    end
  end

  describe "check_now/1" do
    test "performs an immediate check and records it as manual" do
      service = service_fixture(url: TargetServer.url("/status/500"))
      next_check_at = service.next_check_at

      assert {:ok, %{service: s, check: check}} = Monitoring.check_now(service)
      assert check.manual
      assert check.result == :down
      assert check.status_code == 500
      assert s.status == :down
      assert s.last_error == "HTTP 500"
      # The regular schedule is unchanged.
      assert s.next_check_at == next_check_at
    end

    test "counts toward incident series" do
      service = service_fixture(url: TargetServer.url("/status/503"))
      for _ <- 1..3, do: {:ok, _} = Monitoring.check_now(service.id)
      assert %Incident{reason: "HTTP 503"} = Monitoring.get_open_incident(service.id)
    end

    test "re-validates the URL before the request" do
      # Stored URL bypassing validation (e.g. DNS changed after saving).
      Stub.put("now-private.checknow.test", [{192, 168, 5, 5}])
      service = service_fixture(url: "http://now-private.checknow.test/")
      assert {:ok, %{check: check}} = Monitoring.check_now(service)
      assert check.result == :down
      assert check.error =~ "Blocked"
    end

    test "returns not_found for a missing service" do
      assert {:error, :not_found} = Monitoring.check_now(-1)
    end
  end

  describe "PubSub events" do
    test "service lifecycle events" do
      Events.subscribe_admin()
      Events.subscribe_public()

      {:ok, private} =
        Monitoring.create_service(%{
          name: "Private",
          url: TargetServer.url("/ok"),
          interval_minutes: 1
        })

      private_id = private.id
      assert_receive {:monitoring, :service_created, %{service: %{id: ^private_id}}}
      refute_receive {:public_status, _, %{service: %{id: ^private_id}}}

      {:ok, public} = Monitoring.update_service(private, %{public: true})
      assert_receive {:monitoring, :service_updated, %{service: %{id: ^private_id, public: true}}}
      assert_receive {:public_status, :service_updated, %{service: %{id: ^private_id} = pub}}
      refute Map.has_key?(pub, :url)

      {:ok, hidden} = Monitoring.update_service(public, %{public: false})
      assert_receive {:public_status, :service_removed, %{service_id: id}} when id == private.id

      {:ok, _} = Monitoring.update_service(hidden, %{public: true})
      assert_receive {:public_status, :service_updated, %{service: %{id: ^private_id}}}
      {:ok, _} = Monitoring.delete_service(Monitoring.get_service!(private.id))
      assert_receive {:monitoring, :service_deleted, %{service: %{id: ^private_id}}}
      assert_receive {:public_status, :service_removed, %{service_id: id}} when id == private.id
    end

    test "check, status and incident events; private services stay off the public topic" do
      public = service_fixture(public: true)
      private = service_fixture(public: false)
      Events.subscribe_admin()
      Events.subscribe_public()
      Events.subscribe_service(public.id)

      for s <- [public, private], r <- [:down, :down, :down] do
        Monitoring.record_check(s.id, result(r))
      end

      for s <- [public, private], r <- [:up, :up] do
        Monitoring.record_check(s.id, result(r))
      end

      pid = public.id
      prid = private.id

      # Admin topic gets everything for both services.
      for id <- [pid, prid] do
        assert_receive {:monitoring, :check_completed, %{service: %{id: ^id}, check: %Check{}}}

        assert_receive {:monitoring, :status_changed,
                        %{service: %{id: ^id}, from: :pending, to: :down}}

        assert_receive {:monitoring, :incident_opened,
                        %{service: %{id: ^id}, incident: %Incident{}}}

        assert_receive {:monitoring, :status_changed,
                        %{service: %{id: ^id}, from: :down, to: :up}}

        assert_receive {:monitoring, :incident_resolved,
                        %{service: %{id: ^id}, incident: %Incident{ended_at: %DateTime{}}}}
      end

      # Public topic: only the public service, sanitized payloads.
      assert_receive {:public_status, :check_completed, %{service: %{id: ^pid}, check: check}}
      refute Map.has_key?(check, :error)
      assert_receive {:public_status, :status_changed, %{service: %{id: ^pid}, to: :down}}

      assert_receive {:public_status, :incident_opened,
                      %{incident: %{service_id: ^pid, reason: "HTTP 503"}}}

      assert_receive {:public_status, :incident_resolved, %{incident: %{service_id: ^pid}}}

      refute_received {:public_status, _, %{service: %{id: ^prid}}}

      # Per-service topic.
      assert_received {:monitoring, :check_completed, %{service: %{id: ^pid}}}
    end

    test "check_now broadcasts check_completed" do
      service = service_fixture()
      Events.subscribe_service(service.id)
      {:ok, _} = Monitoring.check_now(service)
      assert_receive {:monitoring, :check_completed, %{check: %Check{manual: true, result: :up}}}
    end
  end

  describe "visibility" do
    test "only public services are listed for the public" do
      public = service_fixture(public: true, name: "Public one")
      private = service_fixture(public: false, name: "Private one")

      assert Enum.map(Monitoring.list_public_services(), & &1.id) == [public.id]
      assert Monitoring.get_public_service(public.id)
      refute Monitoring.get_public_service(private.id)
      assert length(Monitoring.list_services()) == 2
    end

    test "public incident listing excludes private services" do
      public = service_fixture(public: true)
      private = service_fixture(public: false)
      incident_fixture(public, DateTime.utc_now())
      incident_fixture(private, DateTime.utc_now())

      assert [%{service_id: id}] = Monitoring.list_incidents(public_only: true)
      assert id == public.id
      assert length(Monitoring.list_incidents()) == 2
    end
  end
end
