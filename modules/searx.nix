{ config, lib, pkgs, ... }:

let
  searxPort = 8888;
in
{
  services.searx = {
    enable = true;
    package = pkgs.searxng;
    runInUwsgi = false;
    redisCreateLocally = true;
    environmentFile = "/etc/searx/env";
    settings = {
      server = {
        bind_address = "127.0.0.1";
        port = searxPort;
        secret_key = "@SEARX_SECRET_KEY@";
      };
      general = {
        instance_name = "SearXNG";
        donation_url = false;
        contact_url = false;
        privacypolicy_url = false;
        enable_metrics = false;
      };
      search = {
        safe_search = 2;
        autocomplete = "duckduckgo";
      };
    };
  };

  # Auto-generate secret key if not present
  system.activationScripts.searx-secret = lib.mkIf config.services.searx.enable ''
    if [ ! -f /etc/searx/env ]; then
      mkdir -p /etc/searx
      echo "SEARX_SECRET_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '/+\n=' | head -c 64)" > /etc/searx/env
      chmod 600 /etc/searx/env
    fi
  '';

  # Expose on tailnet only via tailscale serve
  systemd.services.tailscale-serve-searx = {
    description = "Tailscale serve for SearXNG (tailnet-only)";
    after = [ "tailscaled.service" "searx.service" ];
    requires = [ "tailscaled.service" "searx.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg ${toString searxPort}";
      # No ExecStop -- tailscale serve config persists in tailscaled state.
      # Use `tailscale serve --off` manually if you ever need to tear it down.
    };
  };
}
