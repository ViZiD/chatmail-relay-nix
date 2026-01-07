{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    getExe'
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    mkPackageOption
    optional
    types
    ;
  cfg = config.services.chatmail;
  chatmailLib = import ./lib.nix { inherit lib; };
  iniFormat = pkgs.formats.ini { };
  boolToLower = b: if b then "true" else "false";
  chatmailIniFile = iniFormat.generate "chatmail.ini" {
    params = {
      mail_domain = cfg.domain;
      max_user_send_per_minute = cfg.maxUserSendPerMinute;
      max_mailbox_size = cfg.maxMailboxSize;
      max_message_size = cfg.maxMessageSize;
      delete_mails_after = cfg.deleteMailsAfter;
      delete_large_after = cfg.deleteLargeAfter;
      delete_inactive_users_after = cfg.inactiveUserDays;
      username_min_length = cfg.usernameMinLength;
      username_max_length = cfg.usernameMaxLength;
      password_min_length = cfg.passwordMinLength;
      passthrough_senders = concatStringsSep " " cfg.passthroughSenders;
      passthrough_recipients = concatStringsSep " " cfg.passthroughRecipients;
      mailboxes_dir = cfg.vmailDir;
      passdb_path = "${cfg.vmailDir}/passdb.sqlite";
      filtermail_smtp_port = cfg.filtermail.outgoingPort;
      filtermail_smtp_port_incoming = cfg.filtermail.incomingPort;
      postfix_reinject_port = cfg.filtermail.reinjectOutgoingPort;
      postfix_reinject_port_incoming = cfg.filtermail.reinjectIncomingPort;
      imap_compress = boolToLower cfg.dovecot.imapCompress;
      imap_rawlog = boolToLower cfg.dovecot.imapRawlog;
      disable_ipv6 = boolToLower cfg.disableIpv6;
      privacy_mail = cfg.privacyMail;
    }
    // lib.optionalAttrs (cfg.acme.enable && cfg.acme.email != null) {
      acme_email = cfg.acme.email;
    }
    // lib.optionalAttrs (cfg.mtail.enable && cfg.mtail.address != "") {
      mtail_address = cfg.mtail.address;
    }
    // lib.optionalAttrs (!cfg.irohRelay.enable) {
      iroh_relay = cfg.irohRelay.externalUrl;
    }
    // lib.optionalAttrs (cfg.www.folder != null) {
      www_folder = cfg.www.folder;
    }
    // lib.optionalAttrs (cfg.privacyPostal != null) {
      privacy_postal = cfg.privacyPostal;
    } // lib.optionalAttrs (cfg.privacyPdo != null) {
      privacy_pdo = cfg.privacyPdo;
    } // lib.optionalAttrs (cfg.privacySupervisor != null) {
      privacy_supervisor = cfg.privacySupervisor;
    };
  };
in
{
  options.services.chatmail = {
    enable = mkEnableOption "Chatmail relay server";
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to open firewall ports for chatmail services.
        Opens ports for SMTP (25), HTTP (80), HTTPS (443), SMTPS (465),
        Submission (587), IMAPS (993), and TURN if enabled.
      '';
    };
    package = mkPackageOption pkgs "chatmaild" {
      extraDescription = ''
        The chatmaild package provides doveauth, filtermail, metadata,
        expire, lastlogin, and other chatmail services.
      '';
    };
    domain = mkOption {
      type = types.str;
      example = "chat.example.org";
      description = ''
        Chatmail domain (FQDN). This is used for everything:
        - Email addresses: user@chat.example.org
        - Server hostname: chat.example.org
        - SSL certificates: chat.example.org
        This matches upstream relay's mail_domain setting.
      '';
    };
    privacyMail = mkOption {
      type = types.str;
      example = "privacy@example.org";
      description = "Privacy contact email address.";
    };
    privacyPostal = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "Example GmbH, Street 1, 12345 City, Germany";
      description = "Postal address of privacy contact.";
    };
    privacyPdo = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "Data Protection Officer, Example GmbH";
      description = "Postal address of the privacy data officer.";
    };
    privacySupervisor = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "State Data Protection Authority";
      description = "Postal address of the privacy supervisor authority.";
    };
    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/chatmail";
      description = "Directory for chatmail state and databases.";
    };
    vmailDir = mkOption {
      type = types.path;
      default = "/var/vmail";
      description = "Base directory for user maildirs.";
    };
    configFile = mkOption {
      type = types.path;
      default = "/etc/chatmail.ini";
      readOnly = true;
      description = "Path to chatmail configuration file (managed by NixOS).";
    };
    user = mkOption {
      type = types.str;
      default = "chatmail";
      description = "User account for chatmail services.";
    };
    group = mkOption {
      type = types.str;
      default = "chatmail";
      description = "Group for chatmail services.";
    };
    usernameMinLength = mkOption {
      type = types.ints.positive;
      default = 9;
      description = "Minimum username length.";
    };
    usernameMaxLength = mkOption {
      type = types.ints.positive;
      default = 9;
      description = "Maximum username length.";
    };
    passwordMinLength = mkOption {
      type = types.ints.positive;
      default = 9;
      description = "Minimum password length.";
    };
    maxUserSendPerMinute = mkOption {
      type = types.ints.positive;
      default = 60;
      description = "Maximum emails a user can send per minute.";
    };
    maxMailboxSize = mkOption {
      type = types.str;
      default = "500M";
      description = "Maximum mailbox size per user.";
    };
    maxMessageSize = mkOption {
      type = types.int;
      default = 31457280; # 30MB
      description = "Maximum message size in bytes.";
    };
    deleteMailsAfter = mkOption {
      type = types.str;
      default = "20";
      description = "Delete emails older than this many days.";
    };
    deleteLargeAfter = mkOption {
      type = types.str;
      default = "7";
      description = "Delete large emails (>200k) older than this many days.";
    };
    inactiveUserDays = mkOption {
      type = types.ints.positive;
      default = 90;
      description = "Delete users inactive for this many days.";
    };
    passthroughSenders = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "notifications@example.org" ];
      description = "Senders allowed to bypass encryption check.";
    };
    passthroughRecipients = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "admin@example.org" ];
      description = "Recipients allowed to receive unencrypted mail.";
    };
    disableIpv6 = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Disable IPv6 support.
        Use this on systems without IPv6 connectivity.
      '';
    };
    debug = mkEnableOption "debug mode for verbose logging in postfix and dovecot";
    newAccount = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable /new endpoint for account registration.
          Allows Delta Chat to create new accounts via POST request.
        '';
      };
    };
    postfix = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Postfix MTA.";
      };
      smtpBanner = mkOption {
        type = types.str;
        default = "$myhostname ESMTP";
        description = "SMTP greeting banner.";
      };
    };
    dovecot = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Dovecot IMAP server.";
      };
      protocols = mkOption {
        type = types.listOf types.str;
        default = [ "imap" "lmtp" ];
        description = "Dovecot protocols to enable.";
      };
      imapCompress = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable IMAP COMPRESS extension (RFC 4978).
          Note: This disables IMAP hibernation.
        '';
      };
      imapRawlog = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable IMAP rawlog for debugging.
          Logs IMAP protocol in per-user .in/.out files.
          WARNING: Generates large log files, use with caution on production.
        '';
      };
      vmailUid = mkOption {
        type = types.nullOr types.int;
        default = null;
        example = 5000;
        description = ''
          UID for vmail user. If null, dovecot will accept any UID
          (resolved from system user). Set this only if you need
          strict UID restrictions.
        '';
      };
      vmailGid = mkOption {
        type = types.nullOr types.int;
        default = null;
        example = 5000;
        description = ''
          GID for vmail group. If null, dovecot will accept any GID
          (resolved from system group). Set this only if you need
          strict GID restrictions.
        '';
      };
    };
    nginx = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Nginx web server.";
      };
      enableALPN = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable ALPN multiplexing on port 443.
          Allows HTTPS, IMAPS, SMTPS to share port 443.
        '';
      };
    };
    dkim = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable DKIM signing via OpenDKIM.";
      };
      selector = mkOption {
        type = types.str;
        default = "opendkim";
        description = ''
          DKIM selector name.
          Following upstream relay project, this defaults to "opendkim".
        '';
      };
      keyBits = mkOption {
        type = types.ints.positive;
        default = 2048;
        description = "DKIM key size in bits.";
      };
      privateKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/dkim-private-key";
        description = ''
          Path to an externally managed DKIM private key file.
          If set, the module will use this key instead of auto-generating one.
          The file must be readable by the opendkim user.
          This is useful for:
          - Managing DKIM keys with sops-nix or agenix
          - Using the same DKIM key across multiple deployments
          - Key rotation with external tooling
          If null (default), a key will be auto-generated on first start
          and stored in /var/lib/dkim/.
        '';
      };
    };
    acme = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable ACME/Let's Encrypt certificates.";
      };
      email = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Email for Let's Encrypt notifications.";
      };
    };
    filtermail = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable encryption enforcement.";
      };
      outgoingPort = mkOption {
        type = types.port;
        default = 10080;
        description = "Port for filtermail-outgoing.";
      };
      incomingPort = mkOption {
        type = types.port;
        default = 10081;
        description = "Port for filtermail-incoming.";
      };
      reinjectOutgoingPort = mkOption {
        type = types.port;
        default = 10025;
        description = "Reinject port for outgoing mail.";
      };
      reinjectIncomingPort = mkOption {
        type = types.port;
        default = 10026;
        description = "Reinject port for incoming mail.";
      };
    };
    metadata = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable metadata service for push notifications.";
      };
      port = mkOption {
        type = types.port;
        default = 8000;
        description = "Metadata service port.";
      };
      database = mkOption {
        type = types.path;
        default = "/var/lib/chatmail/metadata.db";
        description = "Path to metadata SQLite database.";
      };
      socketPath = mkOption {
        type = types.path;
        default = "/run/chatmail-metadata/metadata.socket";
        description = "Path to metadata dict socket for Dovecot.";
      };
    };
    lastlogin = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable last login tracking.";
      };
      socketPath = mkOption {
        type = types.path;
        default = "/run/chatmail-lastlogin/lastlogin.socket";
        description = "Path to lastlogin dict socket.";
      };
    };
    turn = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable TURN server (coturn).";
      };
      port = mkOption {
        type = types.port;
        default = 3478;
        description = "TURN listening port.";
      };
      minPort = mkOption {
        type = types.port;
        default = 49152;
        description = "Minimum relay port.";
      };
      maxPort = mkOption {
        type = types.port;
        default = 65535;
        description = "Maximum relay port.";
      };
      realm = mkOption {
        type = types.str;
        default = "";
        description = "TURN realm (empty = use domain).";
      };
    };
    metrics = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable metrics collection.";
      };
      interval = mkOption {
        type = types.str;
        default = "*:0/5";
        description = "Collection interval (systemd timer).";
      };
      outputDir = mkOption {
        type = types.path;
        default = "/var/www/chatmail-metrics";
        description = "Directory for metrics output files (metrics.txt).";
      };
    };
    expire = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable user cleanup.";
      };
      schedule = mkOption {
        type = types.str;
        default = "*-*-* 00:02:00";
        description = "Cleanup schedule (systemd timer format).";
      };
      verbose = mkOption {
        type = types.bool;
        default = true;
        description = "Enable verbose logging for expire service.";
      };
    };
    fsreport = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable filesystem report service.";
      };
      schedule = mkOption {
        type = types.str;
        default = "*-*-* 08:02:00";
        description = "Report generation schedule (default: daily at 8:02 AM).";
      };
    };
  };
  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = "/var/empty";
      description = "Chatmail services user";
    };
    users.groups.${cfg.group} = { };
    users.users.vmail = {
      home = cfg.vmailDir;
      createHome = true;
    };
    environment.systemPackages = [ cfg.package ];
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 vmail vmail -"
      "d ${cfg.vmailDir} 0755 vmail vmail -"
      "d /run/chatmail 0755 ${cfg.user} ${cfg.group} -"
      "d /run/chatmail-metadata 0755 vmail vmail -"
      "d /run/chatmail-lastlogin 0755 vmail vmail -"
      "d /run/doveauth 0755 vmail vmail -"
    ] ++ optional cfg.metrics.enable
      "d ${cfg.metrics.outputDir} 0755 vmail vmail -";
    environment.etc."chatmail.ini".source = chatmailIniFile;
    boot.kernel.sysctl = {
      "fs.inotify.max_user_instances" = 65535;
      "fs.inotify.max_user_watches" = 65535;
    };
    systemd.services.chatmail-doveauth = chatmailLib.mkChatmailService {
      inherit cfg;
      description = "Chatmail Dovecot authentication service";
      user = "vmail";
      group = "vmail";
      execStart = concatStringsSep " " [
        (getExe' cfg.package "doveauth")
        "/run/doveauth/doveauth.socket"
        cfg.configFile
      ];
      hardeningType = "unix";
      runtimeDirectory = "doveauth";
      readWritePaths = [ cfg.vmailDir "/run/doveauth" ];
      extraUnitConfig = {
        before = [ "dovecot.service" ];
      };
    };
    systemd.services.chatmail-lastlogin = mkIf cfg.lastlogin.enable (
      chatmailLib.mkChatmailService {
        inherit cfg;
        description = "Chatmail last login tracking";
        user = "vmail";
        group = "vmail";
        execStart = concatStringsSep " " [
          (getExe' cfg.package "lastlogin")
          cfg.lastlogin.socketPath
          cfg.configFile
        ];
        hardeningType = "unix";
        runtimeDirectory = "chatmail-lastlogin";
        readWritePaths = [ cfg.vmailDir cfg.stateDir "/run/chatmail-lastlogin" ];
        extraUnitConfig = {
          before = [ "dovecot.service" ];
        };
      }
    );
    systemd.services.chatmail-filtermail-outgoing = mkIf cfg.filtermail.enable (
      chatmailLib.mkChatmailService {
        inherit cfg;
        description = "Chatmail outgoing mail encryption filter";
        user = "vmail";
        group = "vmail";
        execStart = concatStringsSep " " [
          (getExe' cfg.package "filtermail")
          cfg.configFile
          "outgoing"
        ];
        hardeningType = "network";
        extraUnitConfig = {
          before = [ "postfix.service" ];
        };
      }
    );
    systemd.services.chatmail-filtermail-incoming = mkIf cfg.filtermail.enable (
      chatmailLib.mkChatmailService {
        inherit cfg;
        description = "Chatmail incoming mail encryption filter";
        user = "vmail";
        group = "vmail";
        execStart = concatStringsSep " " [
          (getExe' cfg.package "filtermail")
          cfg.configFile
          "incoming"
        ];
        hardeningType = "network";
        extraUnitConfig = {
          before = [ "postfix.service" ];
        };
      }
    );
    systemd.services.chatmail-metadata = mkIf cfg.metadata.enable (
      chatmailLib.mkChatmailService {
        inherit cfg;
        description = "Chatmail metadata service for push notifications";
        user = "vmail";
        group = "vmail";
        execStart = concatStringsSep " " [
          (getExe' cfg.package "chatmail-metadata")
          cfg.metadata.socketPath
          cfg.configFile
        ];
        hardeningType = "network";
        runtimeDirectory = "chatmail-metadata";
        stateDirectory = "chatmail";
        readWritePaths = [ cfg.vmailDir cfg.stateDir "/run/chatmail-metadata" ];
        extraUnitConfig = {
          before = [ "dovecot.service" ];
        };
      }
    );
    systemd.services.chatmail-expire = mkIf cfg.expire.enable {
      description = "Chatmail user expiration service";
      serviceConfig = mkMerge [
        chatmailLib.commonHardening
        {
          Type = "oneshot";
          User = "vmail";
          Group = "vmail";
          ExecStart = concatStringsSep " " (
            [
              (getExe' cfg.package "chatmail-expire")
              cfg.configFile
            ]
            ++ optional cfg.expire.verbose "-v"
            ++ [ "--remove" ]
          );
          ReadWritePaths = [ cfg.vmailDir cfg.stateDir ];
        }
      ];
    };
    systemd.timers.chatmail-expire = mkIf cfg.expire.enable {
      description = "Timer for chatmail user expiration";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.expire.schedule;
        Persistent = true;
      };
    };
    systemd.services.chatmail-metrics = mkIf cfg.metrics.enable {
      description = "Chatmail metrics collection";
      after = [ "systemd-tmpfiles-setup.service" ];
      requires = [ "systemd-tmpfiles-setup.service" ];
      script = ''
        ${getExe' cfg.package "chatmail-metrics"} ${cfg.vmailDir} > ${cfg.metrics.outputDir}/metrics.txt
      '';
      serviceConfig = mkMerge [
        chatmailLib.commonHardening
        {
          Type = "oneshot";
          User = "vmail";
          Group = "vmail";
          ReadWritePaths = [ cfg.vmailDir cfg.metrics.outputDir ];
        }
      ];
    };
    systemd.timers.chatmail-metrics = mkIf cfg.metrics.enable {
      description = "Timer for chatmail metrics collection";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.metrics.interval;
        Persistent = true;
      };
    };
    systemd.services.chatmail-fsreport = mkIf cfg.fsreport.enable {
      description = "Chatmail filesystem report";
      serviceConfig = mkMerge [
        chatmailLib.commonHardening
        {
          Type = "oneshot";
          User = "vmail";
          Group = "vmail";
          ExecStart = "${getExe' cfg.package "chatmail-fsreport"} ${cfg.configFile}";
          ReadWritePaths = [ cfg.vmailDir cfg.stateDir ];
        }
      ];
    };
    systemd.timers.chatmail-fsreport = mkIf cfg.fsreport.enable {
      description = "Timer for chatmail filesystem report";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.fsreport.schedule;
        Persistent = true;
      };
    };
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts =
        [
          25
          80
          143
          443
          465
          587
          993
        ]
        ++ optional cfg.turn.enable cfg.turn.port;
      allowedUDPPorts = optional cfg.turn.enable cfg.turn.port;
      allowedUDPPortRanges = optional cfg.turn.enable {
        from = cfg.turn.minPort;
        to = cfg.turn.maxPort;
      };
    };
    assertions = [
      {
        assertion = cfg.domain != "";
        message = "services.chatmail.domain must be set";
      }
      {
        assertion = cfg.acme.enable -> (cfg.acme.email != null);
        message = "services.chatmail.acme.email must be set when ACME is enabled";
      }
      {
        assertion = cfg.usernameMinLength <= cfg.usernameMaxLength;
        message = "services.chatmail.usernameMinLength must be <= usernameMaxLength";
      }
    ];
    warnings =
      optional (cfg.dkim.enable && cfg.dkim.keyBits < 2048)
        "DKIM key size less than 2048 bits is not recommended"
      ++ optional (!cfg.filtermail.enable)
        "Filtermail disabled - cleartext emails will be allowed (not recommended)"
      ++ optional (cfg.maxMessageSize > 50 * 1024 * 1024)
        "Message size limit over 50MB may cause performance issues";
  };
}
