{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    mkIf
    optional
    ;
  cfg = config.services.chatmail;
in
{
  config = mkIf (cfg.enable && cfg.acme.enable) {
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = cfg.acme.email;
      };
      certs.${cfg.domain} = {
        email = cfg.acme.email;
        webroot = "/var/lib/acme/acme-challenge";
        group = "acme";
        keyType = "ec256";
        renewInterval = "daily";
        postRun = ''
          echo "ACME certificate renewed for ${cfg.domain}, reloading services..."
          ${lib.optionalString cfg.postfix.enable ''
            if systemctl is-active --quiet postfix.service; then
              systemctl reload postfix.service && echo "postfix reloaded" || echo "WARNING: postfix reload failed"
            fi
          ''}
          ${lib.optionalString cfg.dovecot.enable ''
            if systemctl is-active --quiet dovecot.service; then
              systemctl reload dovecot.service && echo "dovecot reloaded" || echo "WARNING: dovecot reload failed"
            fi
          ''}
          ${lib.optionalString cfg.nginx.enable ''
            if systemctl is-active --quiet nginx.service; then
              systemctl reload nginx.service && echo "nginx reloaded" || echo "WARNING: nginx reload failed"
            fi
          ''}
          ${lib.optionalString cfg.turn.enable ''
            if systemctl is-active --quiet chatmail-turn.service; then
              systemctl restart chatmail-turn.service && echo "chatmail-turn restarted" || echo "WARNING: chatmail-turn restart failed"
            fi
          ''}
          echo "ACME postRun completed"
        '';
        extraDomainNames = [ "www.${cfg.domain}" "mta-sts.${cfg.domain}" ];
      };
    };
    services.nginx.virtualHosts.${cfg.domain} = mkIf cfg.nginx.enable {
      useACMEHost = cfg.domain;
      forceSSL = true;
      locations."/.well-known/acme-challenge" = {
        root = "/var/lib/acme/acme-challenge";
      };
    };
    services.nginx.virtualHosts."${cfg.domain}-http" = mkIf cfg.nginx.enable {
      serverName = cfg.domain;
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::]";
          port = 80;
        }
      ];
      locations."/.well-known/acme-challenge" = {
        root = "/var/lib/acme/acme-challenge";
      };
      locations."/" = {
        return = "301 https://${cfg.domain}$request_uri";
      };
    };
    systemd.services."acme-order-renew-${cfg.domain}" = {
      after = [ "nginx.service" ];
      wants = [ "nginx.service" ];
    };
    assertions = [
      {
        assertion = cfg.acme.email != null && cfg.acme.email != "";
        message = ''
          services.chatmail.acme.email must be set when ACME is enabled.
          This email is required by Let's Encrypt for certificate notifications.
        '';
      }
      {
        assertion = cfg.nginx.enable;
        message = ''
          ACME requires nginx to be enabled for HTTP-01 challenge.
          Set services.chatmail.nginx.enable = true;
        '';
      }
    ];
    warnings = optional (cfg.acme.email == null)
      "ACME email not set - certificate expiration notifications will not be sent";
  };
}
