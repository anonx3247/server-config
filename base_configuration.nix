# Base NixOS configuration that accepts users and domain parameters
# This is used as a template to generate the final configuration.nix

{ config, lib, pkgs, users, domain, web_domain_prefix, ... }:

let
  # Read SSH key from file
  sshKeyFile = ./ssh_key;
  rootSshKey = if builtins.pathExists sshKeyFile 
    then lib.strings.removeSuffix "\n" (builtins.readFile sshKeyFile)
    else throw "SSH key file 'ssh_key' not found. Please create it with your public SSH key.";

  # Extract hostname from domain (first part before dot)
  hostname = builtins.head (lib.strings.splitString "." domain);

  # Generate user configuration from list
  # All users get isNormalUser = true by default
  generateUsers = userList: lib.listToAttrs (
    map (userName: {
      name = userName;
      value = {
        isNormalUser = true;
      };
    }) userList
  ) // {
    # Always include vmail system user
    vmail = {
      isSystemUser = true;
      group = "vmail";
    };
    # Root user configuration
    root = {
      openssh.authorizedKeys.keys = [ rootSshKey ];
    };
  };

in
{
  imports =
    [ # Include the results of the hardware scan.
      #(builtins.fetchTarball {
        # Pick a release version you are interested in and set its hash, e.g.
        #url = "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/nixos-25.05/nixos-mailserver-nixos-25.05.tar.gz";
        # To get the sha256 of the nixos-mailserver tarball, we can use the nix-prefetch-url command:
        # release="nixos-25.05"; nix-prefetch-url "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/${release}/nixos-mailserver-${release}.tar.gz" --unpack
        #sha256 = "0jpp086m839dz6xh6kw5r8iq0cm4nd691zixzy6z11c4z2vf8v85";
      #})
      ./hardware-configuration.nix
    ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  # boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.
  boot.loader.grub.device = "/dev/vda"; # or "nodev" for efi only

  networking.hostName = hostname;

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  # users.users.alice = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable 'sudo' for the user.
  #   packages = with pkgs; [
  #     tree
  #   ];
  # };

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # NOTE: since there are no passwords, they must be set manually with `passwd`
  users.users = generateUsers users;

  users.groups.vmail = {};

  # Enable nginx with SSL support
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      "${web_domain_prefix}.${domain}" = {
        enableACME = true;
        forceSSL = true;
        root = "/var/www/${web_domain_prefix}";
        locations."/" = {
          tryFiles = "$uri $uri/ =404";
        };
      };

      "git.${domain}" = {
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

      "mail.${domain}" = {
        enableACME = true;
        forceSSL = true;
      };
    };
  };

  # Manages SMTP
  services.postfix = {
    enable = true;
    enableSmtp = true;
    enableSubmission = true;
    domain = domain;
    hostname = "mail.${domain}";
    postmasterAlias = "admin@${domain}";
    rootAlias = "admin@${domain}";

    # Basic SMTP configuration
    config = {
      inet_interfaces = "all";
      mynetworks = [
        "127.0.0.0/8"
      ];
      smtp_tls_security_level = "may";
      smtpd_milters = "local:/run/opendkim/opendkim.sock";
      non_smtpd_milters = "local:/run/opendkim/opendkim.sock";
      milter_default_action = "accept";
      #content_filter = "${pkgs.spamassassin}/bin/spamassassin";
    };

    # Enable header checks
    enableHeaderChecks = true;
    headerChecks = [
      {
        pattern = "/^X-Spam-Flag:/";
        action = "REDIRECT spam@${domain}";
      }
    ];

    # SSL/TLS configuration
    sslCert = "/var/lib/acme/mail.${domain}/cert.pem";
    sslKey = "/var/lib/acme/mail.${domain}/key.pem";

    # Submission options
    submissionOptions = {
      smtpd_client_restrictions = "permit_sasl_authenticated,reject";
      smtpd_tls_security_level = "may";
      smtpd_sasl_type = "dovecot";
      smtpd_sasl_path = "/var/lib/postfix/queue/private/auth";
      smtpd_sasl_auth_enable = "yes";
      smtpd_tls_auth_only = "yes";
    };
  };

  # Manages IMAP
  services.dovecot2 = {
    enable = true;
    enableImap = true; # Enable IMAP protocol
    enablePop3 = false; # Disable POP3 if not needed
    enableLmtp = false; # Disable LMTP if not needed
    enablePAM = true; # Enable PAM for authentication

    # Mail location and storage settings
    mailLocation = "maildir:/var/spool/mail/%u";
    mailUser = "vmail"; # User for virtual mail storage
    mailGroup = "vmail"; # Group for virtual mail storage
    

    # SSL/TLS settings
    sslServerCert = "/var/lib/acme/mail.${domain}/cert.pem";
    sslServerKey = "/var/lib/acme/mail.${domain}/key.pem";

    # Additional configuration
    extraConfig = ''
      mail_debug = yes
      mail_uid = %u
      mail_gid = %u
      first_valid_uid = 1000
      first_valid_gid = 100
      auth_mechanisms = plain login

      service auth {
        unix_listener /var/lib/postfix/queue/private/auth {
          group = postfix
          mode = 0660
          user = postfix
        }
      }
    '';
  };

  services.spamassassin = {
    enable = true; # Enable SpamAssassin daemon

    # Configuration for SpamAssassin
    config = ''
      rewrite_header Subject [***** SPAM _SCORE_ *****]
      required_score          5.0
      use_bayes               1
      bayes_auto_learn        1
      add_header all Status _YESNO_, score=_SCORE_ required=_REQD_ tests=_TESTS_ autolearn=_AUTOLEARN_ version=_VERSION_
    '';

    # Optional: Enable debug mode if needed
    debug = false;
  };

  # Enable ACME for Let's Encrypt certificates
  security.acme = {
    acceptTerms = true;
    defaults.email = "security@${domain}";
  };

  services.opendkim = {
    enable = true;
    domains = "csl:mail.${domain}";
    selector = "default";
  };

  # Enable gitea service
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

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [80 443 143 993 587 465 25];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?

}

