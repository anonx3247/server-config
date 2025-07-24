# Email server module
# Handles mail server configuration with postfix, dovecot, spamassassin, and opendkim

{ config, lib, pkgs, domain, users, ... }:

let
  # Generate user configuration from list
  # All users get isNormalUser = true by default for email access
  generateEmailUsers = userList: lib.listToAttrs (
    map (userName: {
      name = userName;
      value = {
        isNormalUser = true;
      };
    }) userList
  ) // {
    # Always include vmail system user for mail handling
    vmail = {
      isSystemUser = true;
      group = "vmail";
    };
  };

  allowedSenders = lib.listToAttrs (
    map (user: {
      "${user}@${domain}" = "OK";
    }) users
  );

  # Convert the allowed senders to the format Postfix expects
  senderWhitelist = lib.mkDefault (
    builtins.mapAttrsToList (key: value: "${key} ${value}") allowedSenders
  );

  senderWhitelistFile = pkgs.writeText "sender_whitelist" senderWhitelist;

  # Extract hostname from domain (first part before dot)
  hostname = builtins.head (lib.strings.splitString "." domain);
in

{
  # Create email users and vmail system user
  users.users = generateEmailUsers users;

  # Create vmail group
  users.groups.vmail = {};

  # Add mail-related nginx virtual host
  services.nginx.virtualHosts."mail.${domain}" = {
    enableACME = true;
    forceSSL = true;
  };

  services.nginx.virtualHosts."mx.${domain}" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      return = "301 https://mail.lecaillon.com$request_uri";
    };
  };

  # Postfix - SMTP server
  services.postfix = {
    enable = true;
    enableSmtp = true;
    enableSubmission = true;
    domain = domain;
    origin = domain;
    hostname = "mail.${domain}";
    postmasterAlias = "admin@${domain}";
    rootAlias = "admin@${domain}";
    destination = [
      "mail.${domain}"
      "localhost.${domain}"
      "${domain}"
    ];

    # Basic SMTP configuration
    config = {
      inet_interfaces = "all";
      mynetworks = [
        "127.0.0.0/8"
      ];
      smtp_tls_security_level = "encrypt"; # force encryption 
      smtpd_milters = "inet:127.0.0.1:8891";
      non_smtpd_milters = "inet:127.0.0.1:8891";
      milter_default_action = "tempfail";
      smtpd_client_message_rate_limit = 30; # only 30 emails per hour
      smtpd_client_restrictions = [
        "check_sender_access ${senderWhitelistFile}"
        "permit_mynetworks"
        "permit_sasl_authenticated" 
        "reject_unknown_reverse_client"
        "reject_rbl_client zen.spamhaus.org"
        "reject_rbl_client bl.spamcop.net"
        "reject_rbl_client b.barracudacentral.org"
        "reject_rbl_client dnsbl.sorbs.net"
      ];

      # Remove content_filter for now - SpamAssassin integration via amavis would be more complex
      # content_filter = "spamassassin";
    };

    # Enable header checks (disabled while SpamAssassin is disabled)
    # enableHeaderChecks = true;
    # headerChecks = [
    #   {
    #     pattern = "/^X-Spam-Flag:/";
    #     action = "REDIRECT spam@${domain}";
    #   }
    # ];

    # SSL/TLS configuration
    sslCert = "/var/lib/acme/mail.${domain}/cert.pem";
    sslKey = "/var/lib/acme/mail.${domain}/key.pem";

    # Submission options
    submissionOptions = {
      smtpd_client_restrictions = "permit_sasl_authenticated,reject";
      smtpd_tls_security_level = "encrypt";
      smtpd_sasl_type = "dovecot";
      smtpd_sasl_path = "/var/lib/postfix/queue/private/auth";
      smtpd_sasl_auth_enable = "yes";
      smtpd_tls_auth_only = "yes";
      defer_transports = "smtp"; # Defer to SMTP when MX is not found
    };
  };

  # Dovecot - IMAP server
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

  # SpamAssassin - Anti-spam (disabled for now - needs proper integration)
  # services.spamassassin = {
  #   enable = true; # Enable SpamAssassin daemon

  #   # Configuration for SpamAssassin
  #   config = ''
  #     rewrite_header Subject [***** SPAM _SCORE_ *****]
  #     required_score          5.0
  #     use_bayes               1
  #     bayes_auto_learn        1
  #     add_header all Status _YESNO_, score=_SCORE_ required=_REQD_ tests=_TESTS_ autolearn=_AUTOLEARN_ version=_VERSION_
  #   '';

  #   # Optional: Enable debug mode if needed
  #   debug = false;
  # };

  # OpenDKIM - Email authentication
  services.opendkim = {
    enable = true;
    domains = "csl:${domain}";
    selector = "mail";
    socket = "inet:8891@localhost";  # Use inet socket instead of unix socket
    settings = {
      MilterDebug = "6";
      SubDomains = "yes";
      MultipleSignatures = "yes";
      KeyFile = "/var/lib/opendkim/keys/mail.private";
    };
  };

  # Open email-related firewall ports
  networking.firewall.allowedTCPPorts = [ 25 587 465 143 993 ];


  pkgs.writeText "sender_whitelist" senderWhitelist;
} 