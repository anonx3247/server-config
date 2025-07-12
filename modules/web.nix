# Personal web server module
# Handles static website hosting

{ config, lib, pkgs, domain, webPrefix, ... }:

{
  # Add personal website nginx virtual host
  services.nginx.virtualHosts."${webPrefix}.${domain}" = {
    enableACME = true;
    forceSSL = true;
    root = "/var/www/${webPrefix}";
    locations."/" = {
      tryFiles = "$uri $uri/ =404";
    };
  };

  # Create the web directory structure
  systemd.tmpfiles.rules = [
    "d /var/www 0755 root root -"
    "d /var/www/${webPrefix} 0755 root root -"
  ];

  # Optional: Create a simple index.html if none exists
  environment.etc."nixos/web-index.html".text = ''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Welcome to ${webPrefix}.${domain}</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                margin: 50px;
                text-align: center;
            }
            .container {
                max-width: 600px;
                margin: 0 auto;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Welcome to ${webPrefix}.${domain}</h1>
            <p>Your personal website is now running!</p>
            <p>You can replace this file by editing /var/www/${webPrefix}/index.html</p>
            <hr>
            <p>Other services:</p>
            <ul>
                <li><a href="https://mail.${domain}">Mail Server</a></li>
                <li><a href="https://git.${domain}">Git Server</a></li>
            </ul>
        </div>
    </body>
    </html>
  '';

  # Copy the default index.html if /var/www/${webPrefix}/index.html doesn't exist
  systemd.services.web-setup = {
    description = "Setup default web content";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ ! -f /var/www/${webPrefix}/index.html ]; then
        cp /etc/nixos/web-index.html /var/www/${webPrefix}/index.html
        chmod 644 /var/www/${webPrefix}/index.html
      fi
    '';
  };
} 