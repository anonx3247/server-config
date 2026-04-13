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

  allowedSenders = map (user: "${user}@${domain}") users;

  # Convert the allowed senders to the format Postfix expects
  senderWhitelist = builtins.map (email: "${email} OK") allowedSenders;

  senderWhitelistContent = lib.strings.concatStringsSep "\n" senderWhitelist;

  # Extract hostname from domain (first part before dot)
  hostname = builtins.head (lib.strings.splitString "." domain);

  # Wrapper script: pipe through spamc, reinject to port 10025 to avoid content_filter loop
  spamassassinPipe = pkgs.writeShellScript "spamassassin-pipe" ''
    SENDER="$1"
    shift
    ${pkgs.spamassassin}/bin/spamc -f | ${pkgs.msmtp}/bin/msmtp --host=127.0.0.1 --port=10025 --from="$SENDER" -- "$@"
  '';
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

  # Ensure mail services reload when ACME cert is renewed
  security.acme.certs."mail.${domain}".reloadServices = [
    "postfix.service"
    "dovecot2.service"
  ];

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

    # Define map files that Postfix can use
    mapFiles.sender_whitelist = pkgs.writeText "sender_whitelist" senderWhitelistContent;

    # Basic SMTP configuration
    config = {
      inet_interfaces = "all";
      mynetworks = [
        "127.0.0.0/8"
      ];
      smtp_tls_security_level = "encrypt"; # force encryption 
      smtp_bind_address6 = "2001:19f0:5:316b:5400:2ff:feea:4f9d";
      smtpd_milters = "inet:127.0.0.1:8891";
      non_smtpd_milters = "inet:127.0.0.1:8891";
      milter_default_action = "tempfail";
      smtpd_client_message_rate_limit = 30; # only 30 emails per hour
      smtpd_client_restrictions = [
        "check_sender_access hash:/var/lib/postfix/conf/sender_whitelist"
        "permit_mynetworks"
        "permit_sasl_authenticated" 
        "reject_unknown_reverse_client_hostname"
        #"reject_rbl_client zen.spamhaus.org"
        #"reject_rbl_client bl.spamcop.net"
        #"reject_rbl_client b.barracudacentral.org"
        #"reject_rbl_client dnsbl.sorbs.net"
      ];

      content_filter = "spamassassin:dummy";

      # Use Dovecot LDA for local delivery so Sieve filtering runs
      mailbox_command = "${pkgs.dovecot}/libexec/dovecot/deliver";
    };

    # SSL/TLS configuration
    sslCert = "/var/lib/acme/mail.${domain}/cert.pem";
    sslKey = "/var/lib/acme/mail.${domain}/key.pem";

    # SpamAssassin content filter: pipe through spamc, reinject on port 10025
    masterConfig.spamassassin = {
      type = "unix";
      command = "pipe";
      privileged = true;
      args = [
        "flags=DROhu"
        "user=vmail"
        "argv=${spamassassinPipe}"
        "\${sender}"
        "\${recipient}"
      ];
    };

    # Re-injection listener: accepts scanned mail without looping back through content_filter
    masterConfig."127.0.0.1:10025" = {
      type = "inet";
      private = false;
      command = "smtpd";
      args = [
        "-o" "content_filter="
        "-o" "smtpd_delay_reject=no"
        "-o" "smtpd_client_restrictions=permit_mynetworks,reject"
        "-o" "smtpd_recipient_restrictions=permit_mynetworks,reject"
        "-o" "mynetworks=127.0.0.0/8"
        "-o" "smtpd_milters="
        "-o" "receive_override_options=no_unknown_recipient_checks"
      ];
    };

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

      protocol lda {
        mail_plugins = $mail_plugins sieve
      }

      protocol imap {
        mail_plugins = $mail_plugins imap_sieve
      }

      plugin {
        sieve_before = /etc/dovecot/sieve/spam-to-junk.sieve

        # IMAP Sieve: trigger sa-learn when users move messages
        imapsieve_mailbox1_name = Junk
        imapsieve_mailbox1_causes = COPY APPEND
        imapsieve_mailbox1_before = file:/etc/dovecot/sieve/learn-spam.sieve

        imapsieve_mailbox2_name = *
        imapsieve_mailbox2_from = Junk
        imapsieve_mailbox2_causes = COPY
        imapsieve_mailbox2_before = file:/etc/dovecot/sieve/learn-ham.sieve

        sieve_pipe_bin_dir = /etc/dovecot/sieve-pipe
        sieve_global_extensions = +vnd.dovecot.pipe
      }
    '';
  };

  # Dovecot Sieve plugin (pigeonhole) for server-side filtering
  environment.systemPackages = [ pkgs.dovecot_pigeonhole ];

  # Global Sieve script to file spam into Junk
  environment.etc."dovecot/sieve/spam-to-junk.sieve".text = ''
    require ["fileinto", "mailbox"];

    if header :is "X-Spam-Flag" "YES" {
      fileinto :create "Junk";
      stop;
    }
  '';

  # IMAP Sieve: learn spam when user moves mail into Junk
  environment.etc."dovecot/sieve/learn-spam.sieve".text = ''
    require ["vnd.dovecot.pipe", "copy", "imapsieve"];
    pipe :copy "sa-learn-spam.sh";
  '';

  # IMAP Sieve: learn ham when user moves mail out of Junk
  environment.etc."dovecot/sieve/learn-ham.sieve".text = ''
    require ["vnd.dovecot.pipe", "copy", "imapsieve"];
    pipe :copy "sa-learn-ham.sh";
  '';

  # Pipe scripts that sa-learn reads from stdin
  environment.etc."dovecot/sieve-pipe/sa-learn-spam.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      exec ${pkgs.spamassassin}/bin/sa-learn --spam
    '';
  };

  environment.etc."dovecot/sieve-pipe/sa-learn-ham.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      exec ${pkgs.spamassassin}/bin/sa-learn --ham
    '';
  };

  # SpamAssassin - Anti-spam
  services.spamassassin = {
    enable = true;

    config = ''
      rewrite_header Subject [***** SPAM _SCORE_ *****]
      required_score          5.0
      use_bayes               1
      bayes_auto_learn        1
      add_header all Status _YESNO_, score=_SCORE_ required=_REQD_ tests=_TESTS_ autolearn=_AUTOLEARN_ version=_VERSION_
    '';

    debug = false;
  };

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

} 