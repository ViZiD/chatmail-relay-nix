{ lib, ... }:
{
  imports = [
    ./modules/chatmaild.nix
    ./modules/postfix.nix
    ./modules/dovecot.nix
    ./modules/nginx.nix
    ./modules/dkim.nix
    ./modules/acme.nix
    ./modules/turn.nix
    ./modules/iroh-relay.nix
    ./modules/unbound.nix
    ./modules/mtail.nix
    ./modules/www.nix
  ];

  nixpkgs.overlays = [
    (final: prev:
      let
        chatmailPkgs = import ./pkgs { pkgs = final; lib = final.lib; };
      in
      chatmailPkgs // {
        opendkim = chatmailPkgs.opendkim-lua;
        dovecot = prev.dovecot.override { withLua = true; };
      })
  ];

  meta.maintainers = with lib.maintainers; [ ];
}
