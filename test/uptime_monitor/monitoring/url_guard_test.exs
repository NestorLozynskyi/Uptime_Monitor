defmodule UptimeMonitor.Monitoring.UrlGuardTest do
  use ExUnit.Case, async: true

  alias UptimeMonitor.Monitoring.Resolver.Stub
  alias UptimeMonitor.Monitoring.UrlGuard

  defp resolve(url, allowlist \\ []), do: UrlGuard.resolve(url, allowlist: allowlist)

  describe "forbidden IPv4 literals" do
    for ip <- ~w(127.0.0.1 127.255.0.9 10.1.2.3 172.16.5.4 172.31.255.255 192.168.1.1
                 169.254.169.254 169.254.0.1 0.0.0.0 100.64.0.1 192.0.0.8 192.0.2.10
                 198.18.0.1 198.51.100.7 203.0.113.9 224.0.0.1 239.255.255.250
                 240.0.0.1 255.255.255.255) do
      test "#{ip} is blocked" do
        assert {:error, {:blocked, message}} = resolve("http://#{unquote(ip)}/")
        assert message =~ unquote(ip)
      end
    end
  end

  describe "forbidden IPv6 literals" do
    for ip <- ~w(::1 :: fe80::1 fc00::1 fd12:3456::1 ff02::1 ::ffff:127.0.0.1 ::ffff:10.0.0.1
                 ::ffff:8.8.8.8 ::127.0.0.1 2001:db8::1 64:ff9b::a00:1 2002:c0a8:101::1
                 2001::1 fec0::1 100::1) do
      test "[#{ip}] is blocked" do
        assert {:error, {:blocked, _}} = resolve("http://[#{unquote(ip)}]:8080/")
      end
    end
  end

  test "public IPv4 and IPv6 addresses are allowed" do
    assert {:ok, %{ip: {93, 184, 216, 34}, port: 80, scheme: :http}} =
             resolve("http://93.184.216.34/")

    assert {:ok, %{ip: {0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}, port: 443, scheme: :https}} =
             resolve("https://[2606:4700::1111]/status")
  end

  test "only http and https schemes are accepted" do
    for url <- ["ftp://example.com/", "file:///etc/passwd", "javascript:alert(1)", "gopher://x/"] do
      assert {:error, {:invalid, _}} = resolve(url)
    end
  end

  test "URLs without host or with credentials are rejected" do
    assert {:error, {:invalid, _}} = resolve("http:///path")
    assert {:error, {:invalid, _}} = resolve("not a url")
    assert {:error, {:invalid, _}} = resolve("http://user:pass@93.184.216.34/")
  end

  test "a host resolving to a private address is blocked" do
    Stub.put("intranet.example", [{192, 168, 10, 5}])
    assert {:error, {:blocked, message}} = resolve("http://intranet.example/")
    assert message =~ "192.168.10.5"
    assert message =~ "private"
  end

  test "a host is blocked when any of its addresses is forbidden" do
    Stub.put("mixed.example", [{93, 184, 216, 34}, {10, 0, 0, 1}])
    assert {:error, {:blocked, _}} = resolve("http://mixed.example/")

    Stub.put("mixed6.example", [{93, 184, 216, 34}, {0, 0, 0, 0, 0, 0, 0, 1}])
    assert {:error, {:blocked, _}} = resolve("http://mixed6.example/")
  end

  test "a host resolving to the metadata address is blocked" do
    Stub.put("metadata.example", [{169, 254, 169, 254}])
    assert {:error, {:blocked, message}} = resolve("http://metadata.example/latest/meta-data")
    assert message =~ "link-local"
  end

  test "a host resolving to public addresses returns the validated IP (IPv4 preferred)" do
    Stub.put("public.example", [{0x2606, 0x4700, 0, 0, 0, 0, 0, 1}, {93, 184, 216, 34}])

    assert {:ok, %{host: "public.example", ip: {93, 184, 216, 34}}} =
             resolve("https://PUBLIC.example/")
  end

  test "DNS failures are reported" do
    assert {:error, {:dns, message}} = resolve("http://does-not-exist.example/")
    assert message =~ "DNS resolution failed"
  end

  describe "allowlist" do
    test "an empty allowlist blocks loopback" do
      assert {:error, {:blocked, _}} = resolve("http://127.0.0.1/", [])
    end

    test "allows an explicitly listed host name" do
      Stub.put("demo-target", [{172, 18, 0, 3}])
      assert {:error, {:blocked, _}} = resolve("http://demo-target:4100/ok")

      assert {:ok, %{ip: {172, 18, 0, 3}}} =
               resolve("http://demo-target:4100/ok", ["demo-target"])

      # Other private hosts stay blocked.
      Stub.put("other-private", [{172, 18, 0, 4}])
      assert {:error, {:blocked, _}} = resolve("http://other-private/", ["demo-target"])
    end

    test "allows listed IPs and CIDR ranges only" do
      assert {:ok, _} = resolve("http://10.1.2.3/", ["10.1.0.0/16"])
      assert {:error, {:blocked, _}} = resolve("http://10.2.0.1/", ["10.1.0.0/16"])
      assert {:ok, _} = resolve("http://[fd00::5]/", ["fd00::5"])
      assert {:error, {:blocked, _}} = resolve("http://[fd00::6]/", ["fd00::5"])
    end
  end

  test "validate/2 returns a readable message" do
    assert {:error, message} = UrlGuard.validate("http://192.168.0.1/", allowlist: [])
    assert message =~ "not allowed"
    assert :ok = UrlGuard.validate("http://93.184.216.34/", allowlist: [])
  end
end
