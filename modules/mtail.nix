{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    types
    ;
  cfg = config.services.chatmail;
  mtailProgram = pkgs.writeText "delivered_mail.mtail" ''
    counter delivered_mail
    /saved mail to INBOX$/ {
      delivered_mail++
    }
    counter quota_exceeded
    /Quota exceeded \(mailbox for user is full\)$/ {
      quota_exceeded++
    }
    # Essentially the number of outgoing messages.
    counter dkim_signed
    /DKIM-Signature field added/ {
      dkim_signed++
    }
    counter created_accounts
    counter created_ci_accounts
    counter created_nonci_accounts
    /: Created address: (?P<addr>.*)$/ {
      created_accounts++
      $addr =~ /ci-/ {
        created_ci_accounts++
      } else {
        created_nonci_accounts++
      }
    }
    counter postfix_timeouts
    /timeout after DATA/ {
      postfix_timeouts++
    }
    counter postfix_noqueue
    /postfix\/.*NOQUEUE/ {
      postfix_noqueue++
    }
    counter warning_count
    /warning/ {
      warning_count++
    }
    counter filtered_mail_count
    counter encrypted_mail_count
    /Filtering encrypted mail\./ {
      encrypted_mail_count++
      filtered_mail_count++
    }
    counter unencrypted_mail_count
    /Filtering unencrypted mail\./ {
      unencrypted_mail_count++
      filtered_mail_count++
    }
    counter rejected_unencrypted_mail_count
    /Rejected unencrypted mail\./ {
      rejected_unencrypted_mail_count++
    }
  '';
in
{
  options.services.chatmail.mtail = {
    enable = mkEnableOption "mtail log metrics extractor";
    package = mkPackageOption pkgs "mtail" { };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen on for metrics.";
    };
    port = mkOption {
      type = types.port;
      default = 3903;
      description = "Port to expose Prometheus metrics on.";
    };
  };
  config = mkIf (cfg.enable && cfg.mtail.enable) {
    environment.etc."mtail/delivered_mail.mtail".source = mtailProgram;
    systemd.services.chatmail-mtail = {
      description = "Chatmail mtail log metrics extractor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      script = ''
        ${pkgs.systemd}/bin/journalctl -f -o short-iso -n 0 | \
        ${getExe cfg.mtail.package} \
          --address ${cfg.mtail.address} \
          --port ${toString cfg.mtail.port} \
          --progs /etc/mtail \
          --logtostderr \
          --logs -
      '';
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "30s";
        DynamicUser = true;
        SupplementaryGroups = [ "systemd-journal" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
      };
    };
    networking.firewall.allowedTCPPorts = mkIf (cfg.openFirewall && cfg.mtail.address != "127.0.0.1") [
      cfg.mtail.port
    ];
  };
}
