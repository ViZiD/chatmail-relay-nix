{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkPackageOption
    optional
    ;
  inherit (lib.meta) getExe;
  cfg = config.services.chatmail;
  chatmailLib = import ./lib.nix { inherit lib; };
in
{
  options.services.chatmail.turn = {
    package = mkPackageOption pkgs "chatmail-turn" {
      extraDescription = ''
        The chatmail-turn package provides a TURN server
        with integrated credential generation via Unix socket.
      '';
    };
  };
  config = mkIf (cfg.enable && cfg.turn.enable) {
    systemd.services.chatmail-turn = chatmailLib.mkChatmailService {
      inherit cfg;
      description = "Chatmail TURN server for WebRTC relay";
      user = "vmail";
      group = "vmail";
      execStart = "${getExe cfg.turn.package} --realm ${cfg.domain} --socket /run/chatmail-turn/turn.socket";
      hardeningType = "none";
      runtimeDirectory = "chatmail-turn";
      extraUnitConfig = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };
    };
    assertions = [
      {
        assertion = cfg.turn.minPort < cfg.turn.maxPort;
        message = "services.chatmail.turn.minPort must be less than maxPort";
      }
      {
        assertion = !(cfg.turn.port == 443 && cfg.nginx.enable);
        message = "TURN port conflicts with HTTPS (use different port or disable nginx)";
      }
    ];
    warnings =
      optional (cfg.turn.maxPort - cfg.turn.minPort < 1000)
        "TURN relay port range is small (${
          toString (cfg.turn.maxPort - cfg.turn.minPort)
        } ports) - may limit concurrent connections"
      ++ optional (cfg.turn.port == 3478)
        "TURN using standard port 3478 - may be blocked by some firewalls";
  };
}
