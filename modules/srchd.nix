# srchd service module
# Hosts the srchd web UI for viewing experiments

{ config, lib, pkgs, domain, srchdAuth, ... }:

let
  # Use Node.js 22 (latest LTS available in nixpkgs, close to 24)
  nodejs = pkgs.nodejs_22;

  # srchd installation directory
  srchdDir = "/var/lib/srchd";
  srchdPort = 1337;

  # Parse auth credentials if provided
  authArgs = if srchdAuth != "" then "-a ${srchdAuth}" else "";
in

{
  # Install required packages
  environment.systemPackages = with pkgs; [
    nodejs
    git
  ];

  # Create srchd directory
  systemd.tmpfiles.rules = [
    "d ${srchdDir} 0755 root root -"
    "d ${srchdDir}/data 0755 root root -"
  ];

  # srchd systemd service
  systemd.services.srchd = {
    description = "srchd experiment viewer";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    path = [ pkgs.bash pkgs.coreutils pkgs.git nodejs ];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = srchdDir;
      ExecStart = "${nodejs}/bin/node ${srchdDir}/node_modules/.bin/tsx src/srchd.ts serve -p ${toString srchdPort} ${authArgs}";
      Restart = "always";
      RestartSec = 10;

      # Environment
      Environment = [
        "NODE_ENV=production"
        "HOME=${srchdDir}"
      ];
    };

    # Ensure the repo is cloned and dependencies installed before starting
    preStart = ''
      # Clone srchd repo if not present
      if [ ! -d "${srchdDir}/.git" ]; then
        ${pkgs.git}/bin/git clone https://github.com/dust-tt/srchd.git ${srchdDir}
      fi

      # Install dependencies if node_modules doesn't exist
      cd ${srchdDir}
      if [ ! -d "${srchdDir}/node_modules" ]; then
        ${nodejs}/bin/npm install --production=false
      fi

      # Run database migrations
      ${nodejs}/bin/node ${srchdDir}/node_modules/.bin/drizzle-kit migrate || true
    '';
  };

  # Nginx reverse proxy for srchd
  services.nginx.virtualHosts."srchd.${domain}" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString srchdPort}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}
