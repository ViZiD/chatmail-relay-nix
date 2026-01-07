{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    getExe'
    mkIf
    mkOption
    mkPackageOption
    optionalAttrs
    types
    ;
  cfg = config.services.chatmail;
  chatmailLib = import ./lib.nix { inherit lib; };
  tomlFormat = pkgs.formats.toml { };
  irohRelayConfig = tomlFormat.generate "iroh-relay.toml" ({
    enable_relay = true;
    http_bind_addr = "[::]:${toString cfg.irohRelay.port}";
    enable_stun = false;
    enable_metrics = cfg.irohRelay.enableMetrics;
  } // optionalAttrs cfg.irohRelay.enableMetrics {
    metrics_bind_addr = cfg.irohRelay.metricsBindAddr;
  });
in
{
  options.services.chatmail.irohRelay = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable iroh-relay for Delta Chat P2P communication.
        This provides relay functionality for peer-to-peer connections.
      '';
    };
    package = mkPackageOption pkgs "iroh-relay" {
      extraDescription = ''
        The iroh-relay package for P2P relay functionality.
      '';
    };
    port = mkOption {
      type = types.port;
      default = 3340;
      description = "HTTP port for iroh-relay service.";
    };
    enableMetrics = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Prometheus metrics endpoint.";
    };
    metricsBindAddr = mkOption {
      type = types.str;
      default = "127.0.0.1:9092";
      description = "Address for metrics endpoint.";
    };
    externalUrl = mkOption {
      type = types.str;
      default = "";
      example = "https://relay.example.com";
      description = ''
        External iroh relay URL to use when local relay is disabled.
        If empty string, iroh relay functionality is completely disabled.
        Only used when `enable = false`.
      '';
    };
  };
  config = mkIf (cfg.enable && cfg.irohRelay.enable) {
    users.users.iroh = {
      isSystemUser = true;
      group = "iroh";
      description = "iroh-relay service user";
    };
    users.groups.iroh = { };
    systemd.services.iroh-relay = chatmailLib.mkChatmailService {
      inherit cfg;
      description = "Iroh relay for Delta Chat P2P";
      execStart = "${getExe' cfg.irohRelay.package "iroh-relay"} --config-path ${irohRelayConfig}";
      user = "iroh";
      group = "iroh";
      hardeningType = "network";
      extraServiceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
    services.nginx.virtualHosts.${cfg.domain}.locations = mkIf cfg.nginx.enable {
      "/relay" = {
        proxyPass = "http://127.0.0.1:${toString cfg.irohRelay.port}";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };
      "/relay/probe" = {
        proxyPass = "http://127.0.0.1:${toString cfg.irohRelay.port}/relay/probe";
        extraConfig = "proxy_http_version 1.1;";
      };
    };
  };
}
