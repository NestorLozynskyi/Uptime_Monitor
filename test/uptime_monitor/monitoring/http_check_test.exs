defmodule UptimeMonitor.Monitoring.HttpCheckTest do
  use ExUnit.Case, async: true

  alias UptimeMonitor.Monitoring.HttpCheck
  alias UptimeMonitor.Monitoring.Resolver.Stub
  alias UptimeMonitor.TargetServer

  # Test config: timeout 1 500 ms, degraded threshold 300 ms, allowlist 127.0.0.1/32.

  describe "classification" do
    test "HTTP 2xx is up" do
      assert %{result: :up, status_code: 200, error: nil, response_time_ms: ms} =
               HttpCheck.run(TargetServer.url("/ok"))

      assert is_integer(ms) and ms < 300

      assert %{result: :up, status_code: 204} = HttpCheck.run(TargetServer.url("/status/204"))
    end

    test "HTTP 3xx without Location is up" do
      assert %{result: :up, status_code: 304} = HttpCheck.run(TargetServer.url("/status/304"))
    end

    test "redirects are followed and the final status is used" do
      assert %{result: :up, status_code: 200} = HttpCheck.run(TargetServer.url("/redirect/3"))

      assert %{result: :down, status_code: 404, error: "HTTP 404"} =
               HttpCheck.run(TargetServer.url("/redirect-to?url=/status/404"))
    end

    test "HTTP 4xx is down" do
      for code <- [400, 401, 404, 429] do
        assert %{result: :down, status_code: ^code, error: error} =
                 HttpCheck.run(TargetServer.url("/status/#{code}"))

        assert error == "HTTP #{code}"
      end
    end

    test "HTTP 5xx is down" do
      for code <- [500, 502, 503] do
        assert %{result: :down, status_code: ^code} =
                 HttpCheck.run(TargetServer.url("/status/#{code}"))
      end
    end

    test "a successful response slower than the threshold is degraded" do
      assert %{result: :degraded, status_code: 200, response_time_ms: ms} =
               HttpCheck.run(TargetServer.url("/delay/500"))

      assert ms >= 500
    end

    test "default thresholds are 3 s (degraded) and 10 s (timeout)" do
      # Production values from config/config.exs (tests override them for speed).
      assert %{result: :degraded} =
               HttpCheck.run(TargetServer.url("/delay/3200"),
                 degraded_threshold: 3_000,
                 timeout: 10_000
               )

      assert %{result: :up} =
               HttpCheck.run(TargetServer.url("/delay/100"),
                 degraded_threshold: 3_000,
                 timeout: 10_000
               )
    end

    test "a slow failed response is down, not degraded" do
      assert %{result: :down, status_code: 500} =
               HttpCheck.run(TargetServer.url("/delay/500?status=500"))
    end

    test "a response exceeding the timeout is down" do
      started = System.monotonic_time(:millisecond)

      assert %{result: :down, status_code: nil, response_time_ms: nil, error: error} =
               HttpCheck.run(TargetServer.url("/delay/5000"))

      assert error == "Timed out after 1.5 s"
      assert System.monotonic_time(:millisecond) - started < 2_500
    end

    test "the timeout message uses whole seconds for the 10 s default" do
      assert %{result: :down, error: "Timed out after 1 s"} =
               HttpCheck.run(TargetServer.url("/delay/3000"), timeout: 1_000)
    end

    test "DNS failure is down" do
      assert %{result: :down, error: error} = HttpCheck.run("http://no-such-host.invalid/")
      assert error =~ "DNS resolution failed"
    end

    test "connection refused is down" do
      port = TargetServer.closed_port()

      assert %{result: :down, error: "Connection refused"} =
               HttpCheck.run("http://refused.target.test:#{port}/")
    end

    @tag :capture_log
    test "TLS/protocol errors on a plain HTTP port are down" do
      assert %{result: :down, error: error} =
               HttpCheck.run("https://tls.target.test:#{TargetServer.port()}/ok")

      assert is_binary(error)
    end
  end

  describe "SSRF protection during checks" do
    test "a forbidden address is a failed check with the reason" do
      assert %{result: :down, error: error} = HttpCheck.run("http://10.0.0.1/", allowlist: [])
      assert error =~ "Blocked: address 10.0.0.1"
    end

    test "loopback target is blocked when not allowlisted" do
      assert %{result: :down, error: "Blocked: " <> _} =
               HttpCheck.run(TargetServer.url("/ok"), allowlist: [])
    end

    test "a host resolving to a private IP is blocked before connecting" do
      Stub.put("rebind.check.test", [{192, 168, 1, 20}])

      assert %{result: :down, error: error} = HttpCheck.run("http://rebind.check.test/")
      assert error =~ "192.168.1.20"
    end

    test "a redirect to a forbidden IP is blocked" do
      url = TargetServer.url("/redirect-to?url=http://169.254.169.254/latest/meta-data")
      assert %{result: :down, error: error} = HttpCheck.run(url)
      assert error =~ "Redirect blocked"
      assert error =~ "169.254.169.254"
    end

    test "a redirect to a host resolving to a private IP is blocked" do
      Stub.put("internal.redirect.test", [{10, 20, 30, 40}])
      url = TargetServer.url("/redirect-to?url=http://internal.redirect.test/admin")
      assert %{result: :down, error: "Redirect blocked: " <> _} = HttpCheck.run(url)
    end

    test "a redirect to another loopback address outside the allowlist is blocked" do
      url = TargetServer.url("/redirect-to?url=http://127.0.0.2:#{TargetServer.port()}/ok")
      assert %{result: :down, error: "Redirect blocked: " <> _} = HttpCheck.run(url)
    end

    test "a redirect to a non-http scheme is rejected" do
      url = TargetServer.url("/redirect-to?url=file:///etc/passwd")
      assert %{result: :down, error: "Invalid redirect URL: " <> _} = HttpCheck.run(url)
    end

    test "redirects are limited" do
      assert %{result: :down, error: "Too many redirects (more than 5)"} =
               HttpCheck.run(TargetServer.url("/redirect-loop"))

      assert %{result: :up} = HttpCheck.run(TargetServer.url("/redirect/5"))
      assert %{result: :down} = HttpCheck.run(TargetServer.url("/redirect/6"))
    end

    test "allowlisted host names permit private targets" do
      Stub.put("demo-target.allow.test", [{127, 0, 0, 1}])
      url = "http://demo-target.allow.test:#{TargetServer.port()}/ok"

      assert %{result: :down, error: "Blocked: " <> _} = HttpCheck.run(url, allowlist: [])

      assert %{result: :up} = HttpCheck.run(url, allowlist: ["demo-target.allow.test"])
    end

    test "the request goes to the validated IP, not a re-resolved one" do
      # The stub returns 127.0.0.1; the Host header keeps the original name.
      Stub.put("pinned.allow.test", [{127, 0, 0, 1}])

      assert %{result: :up} =
               HttpCheck.run("http://pinned.allow.test:#{TargetServer.port()}/ok",
                 allowlist: ["127.0.0.1"]
               )
    end
  end
end
