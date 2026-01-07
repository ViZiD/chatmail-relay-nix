{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.chatmail;
in
{
  options.services.chatmail.www = {
    root = mkOption {
      type = types.either types.path types.package;
      description = ''
        Root directory for the website.
        Can be any path or package containing static files.
        Default: chatmail-www package with relay templates.
      '';
      example = lib.literalExpression "./my-static-site";
    };
    folder = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/var/www/chatmail";
      description = ''
        Path to www directory for chatmail.ini (relay compatibility).
        This is written to chatmail.ini as www_folder.
        If null, the option is omitted from chatmail.ini.
        Note: In NixOS, the actual web root is controlled by www.root.
        This option exists for compatibility with relay's chatmail.ini format.
      '';
    };
    qrLogo = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Logo to embed in the center of QR code.
        - Default: Delta Chat logo (matches upstream relay)
        - `null`: No logo (simple QR code)
        - path: Custom logo file (PNG with transparency recommended)
      '';
    };
  };

  config.services.chatmail.www = {
    root = lib.mkDefault (pkgs.chatmail-www.override {
      domain = cfg.domain;
      maxUserSendPerMinute = cfg.maxUserSendPerMinute;
      maxMailboxSize = cfg.maxMailboxSize;
      deleteMailsAfter = cfg.deleteMailsAfter;
      deleteInactiveUsersAfter = cfg.inactiveUserDays;
      privacyMail = if cfg.privacyMail != null then cfg.privacyMail else "";
      privacyPostal = if cfg.privacyPostal != null then cfg.privacyPostal else "";
      privacyPdo = if cfg.privacyPdo != null then cfg.privacyPdo else "";
      privacySupervisor = if cfg.privacySupervisor != null then cfg.privacySupervisor else "";
      qrLogo = cfg.www.qrLogo;
    });
    qrLogo = lib.mkDefault pkgs.chatmail-www.defaultLogo;
  };
}
