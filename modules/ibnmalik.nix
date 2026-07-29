# Ibn Malik static website module
# Hosts ibnmalik.org (apex only).
# www.ibnmalik.org is handled by Gandi's web-redirect service at the registrar,
# so we deliberately do NOT define a www vhost here (avoids ACME failures for a
# hostname that does not resolve to this server).
# Static files served from /var/www/ibnmalik.

{ config, lib, pkgs, ... }:

let
  ibnmalikDomain = "ibnmalik.org";
  ibnmalikRoot = "/var/www/ibnmalik";
in
{
  services.nginx.virtualHosts."${ibnmalikDomain}" = {
    enableACME = true;
    forceSSL = true;
    root = ibnmalikRoot;
    locations."/" = {
      tryFiles = "$uri $uri/ =404";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/www 0755 root root -"
    "d ${ibnmalikRoot} 0755 root root -"
  ];
}
