{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    mkIf
    optional
    ;
  cfg = config.services.chatmail;
  loginMapFile = pkgs.writeText "postfix-login_map" ''
    /^(.*)$/	''${1}
  '';
  submissionHeaderCleanup = pkgs.writeText "submission_header_cleanup" ''
    /^Received:/            IGNORE
    /^X-Originating-IP:/    IGNORE
    /^X-Mailer:/            IGNORE
    /^User-Agent:/          IGNORE
    /^Subject:/             REPLACE Subject: [...]
  '';
in
{
  config = mkIf (cfg.enable && cfg.postfix.enable) {
    services.postfix = {
      enable = true;
      settings.main = {
        mynetworks = [
          "127.0.0.0/8"
          "[::ffff:127.0.0.0]/104"
          "[::1]/128"
        ];
        myhostname = cfg.domain;
        mydomain = cfg.domain;
        myorigin = cfg.domain;
        mydestination = "";
        inet_interfaces = "all";
        inet_protocols = if cfg.disableIpv6 then "ipv4" else "all";
        recipient_delimiter = "+";
        smtpd_banner = cfg.postfix.smtpBanner;
        smtpd_tls_chain_files = [
          "/var/lib/acme/${cfg.domain}/key.pem"
          "/var/lib/acme/${cfg.domain}/fullchain.pem"
        ];
        smtpd_tls_security_level = "may";
        smtpd_tls_exclude_ciphers = "aNULL, RC4, MD5, DES";
        tls_preempt_cipherlist = true;
        smtp_tls_CApath = "/etc/ssl/certs";
        smtp_tls_security_level = "verify";
        smtp_tls_servername = "hostname";
        smtp_tls_session_cache_database = "btree:$data_directory/smtp_scache";
        smtp_tls_protocols = ">=TLSv1.2";
        smtp_tls_mandatory_protocols = ">=TLSv1.2";
        smtp_tls_policy_maps = "inline:{nauta.cu=may}";
        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "private/auth";
        virtual_transport = "lmtp:unix:private/dovecot-lmtp";
        virtual_mailbox_domains = cfg.domain;
        mua_client_restrictions = "permit_sasl_authenticated, reject";
        mua_sender_restrictions = "reject_sender_login_mismatch, permit_sasl_authenticated, reject";
        mua_helo_restrictions = "permit_mynetworks, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname, permit";
        smtpd_sender_login_maps = "regexp:${loginMapFile}";
        smtpd_relay_restrictions = concatStringsSep ", " [
          "permit_mynetworks"
          "permit_sasl_authenticated"
          "defer_unauth_destination"
        ];
        message_size_limit = cfg.maxMessageSize;
        mailbox_size_limit = 0;
        biff = false;
        append_dot_mydomain = false;
        readme_directory = "no";
        compatibility_level = "3.6";
        smtpd_peername_lookup = false;
      };
      settings.master = {
        smtp_inet = {
          args =
            (optional cfg.debug "-v")
            ++ [
              "-o" "smtpd_tls_security_level=encrypt"
              "-o" "smtpd_tls_mandatory_protocols=>=TLSv1.2"
              "-o" "smtpd_proxy_filter=127.0.0.1:${toString cfg.filtermail.incomingPort}"
            ];
        };
        submission = {
          type = "inet";
          private = false;
          command = "smtpd";
          maxproc = 5000;
          args = [
            "-o" "syslog_name=postfix/submission"
            "-o" "smtpd_tls_security_level=encrypt"
            "-o" "smtpd_tls_mandatory_protocols=>=TLSv1.3"
            "-o" "smtpd_sasl_auth_enable=yes"
            "-o" "smtpd_sasl_type=dovecot"
            "-o" "smtpd_sasl_path=private/auth"
            "-o" "smtpd_tls_auth_only=yes"
            "-o" "smtpd_reject_unlisted_recipient=no"
            "-o" "smtpd_client_restrictions=$mua_client_restrictions"
            "-o" "smtpd_helo_restrictions=$mua_helo_restrictions"
            "-o" "smtpd_sender_restrictions=$mua_sender_restrictions"
            "-o" "smtpd_recipient_restrictions="
            "-o" "smtpd_relay_restrictions=permit_sasl_authenticated,reject"
            "-o" "smtpd_client_connection_count_limit=1000"
            "-o" "smtpd_proxy_filter=127.0.0.1:${toString cfg.filtermail.outgoingPort}"
          ];
        };
        smtps = {
          type = "inet";
          private = false;
          command = "smtpd";
          maxproc = 5000;
          args = [
            "-o" "syslog_name=postfix/smtps"
            "-o" "smtpd_tls_wrappermode=yes"
            "-o" "smtpd_tls_security_level=encrypt"
            "-o" "smtpd_tls_mandatory_protocols=>=TLSv1.3"
            "-o" "smtpd_sasl_auth_enable=yes"
            "-o" "smtpd_sasl_type=dovecot"
            "-o" "smtpd_sasl_path=private/auth"
            "-o" "smtpd_reject_unlisted_recipient=no"
            "-o" "smtpd_client_restrictions=$mua_client_restrictions"
            "-o" "smtpd_helo_restrictions=$mua_helo_restrictions"
            "-o" "smtpd_sender_restrictions=$mua_sender_restrictions"
            "-o" "smtpd_recipient_restrictions="
            "-o" "smtpd_relay_restrictions=permit_sasl_authenticated,reject"
            "-o" "smtpd_client_connection_count_limit=1000"
            "-o" "smtpd_proxy_filter=127.0.0.1:${toString cfg.filtermail.outgoingPort}"
          ];
        };
        "127.0.0.1:${toString cfg.filtermail.reinjectOutgoingPort}" = {
          type = "inet";
          private = false;
          maxproc = 100;
          command = "smtpd";
          args = [
            "-o" "syslog_name=postfix/reinject"
            "-o" "milter_macro_daemon_name=ORIGINATING"
            "-o" "smtpd_milters=${if cfg.dkim.enable then "unix:opendkim/opendkim.sock" else ""}"
            "-o" "cleanup_service_name=authclean"
          ];
        };
        "127.0.0.1:${toString cfg.filtermail.reinjectIncomingPort}" = {
          type = "inet";
          private = false;
          maxproc = 100;
          command = "smtpd";
          args = [
            "-o" "syslog_name=postfix/reinject_incoming"
            "-o" "smtpd_milters=${if cfg.dkim.enable then "unix:opendkim/opendkim.sock" else ""}"
          ];
        };
        authclean = {
          type = "unix";
          private = false;
          chroot = false;
          maxproc = 0;
          command = "cleanup";
          args = [
            "-o" "header_checks=regexp:${submissionHeaderCleanup}"
          ];
        };
        pickup = {
          private = false;
          wakeup = 60;
          maxproc = 1;
        };
        cleanup = {
          private = false;
          maxproc = 0;
        };
        qmgr = {
          type = "unix";
          private = false;
          chroot = false;
          wakeup = 300;
          maxproc = 1;
        };
        tlsmgr = {
          type = "unix";
          wakeup = 1000;
          wakeupUnusedComponent = false;
          maxproc = 1;
        };
        rewrite = { };
        bounce = {
          maxproc = 0;
        };
        defer = {
          maxproc = 0;
          command = "bounce";
        };
        trace = {
          maxproc = 0;
          command = "bounce";
        };
        verify = {
          maxproc = 1;
        };
        flush = {
          private = false;
          wakeup = 1000;
          wakeupUnusedComponent = false;
          maxproc = 0;
        };
        proxymap = {
          chroot = false;
        };
        proxywrite = {
          chroot = false;
          maxproc = 1;
          command = "proxymap";
        };
        relay = {
          command = "smtp";
          args = [
            "-o" "syslog_name=postfix/$service_name"
          ];
        };
        showq = {
          private = false;
        };
        error = { };
        retry = {
          command = "error";
        };
        discard = { };
        lmtp = { };
        anvil = {
          maxproc = 1;
        };
        scache = {
          maxproc = 1;
        };
        postlog = {
          type = "unix-dgram";
          private = false;
          chroot = false;
          maxproc = 1;
        };
      };
    };
    users.users.postfix.extraGroups = [ "acme" ];
    systemd.services.postfix = {
      after = [
        "chatmail-filtermail-outgoing.service"
        "chatmail-filtermail-incoming.service"
      ];
      wants = [
        "chatmail-filtermail-outgoing.service"
        "chatmail-filtermail-incoming.service"
      ];
      serviceConfig = {
        Restart = "always";
        RestartSec = "30s";
      };
    };
  };
}
