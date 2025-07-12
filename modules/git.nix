# Git server module
# Handles git server configuration with gitea

{ config, lib, pkgs, domain, ... }:

let
  # Extract hostname from domain (first part before dot)
  hostname = builtins.head (lib.strings.splitString "." domain);
in

{
  # Add git-related nginx virtual host
  services.nginx.virtualHosts."git.${domain}" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };

  # Gitea - Git server with web interface
  services.gitea = {
    enable = true;
    database.type = "sqlite3";
    settings = {
      server = {
        DOMAIN = "git.${domain}";
        HTTP_PORT = 3000;
        ROOT_URL = "https://git.${domain}/";
      };
      service = {
        DISABLE_REGISTRATION = false;
      };
    };
  };
} 