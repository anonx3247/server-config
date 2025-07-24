# Base NixOS configuration that accepts users and domain parameters
# This is used as a template to generate the final configuration.nix

{ config, lib, pkgs, users, domain, webPrefix, services, ... }:

let
  # Read SSH key from file
  sshKeyFile = ./ssh_key;
  rootSshKey = if builtins.pathExists sshKeyFile 
    then lib.strings.removeSuffix "\n" (builtins.readFile sshKeyFile)
    else throw "SSH key file 'ssh_key' not found. Please create it with your public SSH key.";

  # Extract hostname from domain (first part before dot)
  hostname = builtins.head (lib.strings.splitString "." domain);

  # Conditionally import service modules
  serviceImports = lib.optionals services.mail [
    (import ./modules/email.nix { inherit config lib pkgs domain users; })
  ] ++ lib.optionals services.git [
    (import ./modules/git.nix { inherit config lib pkgs domain; })
  ] ++ lib.optionals services.web [
    (import ./modules/web.nix { inherit config lib pkgs domain webPrefix; })
  ];

in
{
  imports = [
    # Include the results of the hardware scan
    ./hardware-configuration.nix
    # Import service modules based on enabled services
  ] ++ serviceImports;

  # Use the GRUB 2 boot loader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda"; # or "nodev" for efi only

  # Network configuration
  networking.hostName = hostname;

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
  ];

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Root user configuration (only root, email users are handled by email module)
  users.users.root = {
    openssh.authorizedKeys.keys = [ rootSshKey ];
  };

  # Nginx base configuration (only if web service is enabled)
  services.nginx = lib.mkIf (services.web || services.mail || services.git) {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
  };

  # Fail2Ban configuration
  services.fail2ban.enable = true;


  # ACME configuration for Let's Encrypt certificates (only if web or mail service is enabled)
  security.acme = lib.mkIf (services.web || services.mail || services.git) {
    acceptTerms = true;
    defaults.email = "security@${domain}";
  };

  # Firewall configuration (base ports, modules add their own)
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # System version
  system.stateVersion = "25.05";
}

