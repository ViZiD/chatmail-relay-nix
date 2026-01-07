{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    ;
  cfg = config.services.chatmail;
in
{
  options.services.chatmail.unbound = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable local DNS resolver (Unbound).
        Provides DNS caching, DNSSEC validation, and DNS-over-TLS.
        Following upstream relay project, this is enabled by default.
      '';
    };
    forwardAddresses = mkOption {
      type = types.listOf types.str;
      default = [
        "1.1.1.1@853#cloudflare-dns.com"
        "1.0.0.1@853#cloudflare-dns.com"
      ];
      example = [
        "8.8.8.8"
        "8.8.4.4"
      ];
      description = ''
        Upstream DNS servers to forward queries to.
        Default uses Cloudflare DNS over TLS.
      '';
    };
    enableDNSSEC = mkOption {
      type = types.bool;
      default = true;
      description = "Enable DNSSEC validation.";
    };
  };
  config = mkIf (cfg.enable && cfg.unbound.enable) {
    services.unbound = {
      enable = true;
      enableRootTrustAnchor = cfg.unbound.enableDNSSEC;
      settings = {
        server = {
          interface = [ "127.0.0.1" "::1" ];
          port = 53;
          access-control = [
            "127.0.0.0/8 allow"
            "::1/128 allow"
          ];
          num-threads = 2;
          msg-cache-size = "64m";
          rrset-cache-size = "128m";
          cache-min-ttl = 300;
          cache-max-ttl = 86400;
          hide-identity = true;
          hide-version = true;
          val-clean-additional = cfg.unbound.enableDNSSEC;
          prefetch = true;
          prefetch-key = true;
          harden-glue = true;
          harden-dnssec-stripped = cfg.unbound.enableDNSSEC;
          harden-referral-path = true;
          tls-cert-bundle = "/etc/ssl/certs/ca-certificates.crt";
        };
        forward-zone = [
          {
            name = ".";
            forward-tls-upstream = true;
            forward-addr = cfg.unbound.forwardAddresses;
          }
        ];
      };
    };
    networking.nameservers = [ "127.0.0.1" "::1" ];
    networking.dhcpcd.extraConfig = ''
      nohook resolv.conf
    '';
    systemd.services.postfix = mkIf cfg.postfix.enable {
      after = [ "unbound.service" ];
      wants = [ "unbound.service" ];
    };
    systemd.services.dovecot = mkIf cfg.dovecot.enable {
      after = [ "unbound.service" ];
      wants = [ "unbound.service" ];
    };
    systemd.services."acme-${cfg.domain}" = mkIf cfg.acme.enable {
      after = [ "unbound.service" ];
      wants = [ "unbound.service" ];
    };
    systemd.services.opendkim = mkIf cfg.dkim.enable {
      after = [ "unbound.service" ];
      wants = [ "unbound.service" ];
    };
  };
}
