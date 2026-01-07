{
  description = "Chatmail Relay - NixOS module for Delta Chat email relay server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        nixosModules.default = import ./default.nix;
        nixosModules.chatmail = import ./default.nix;

        overlays.default =
          final: prev:
          let
            chatmailPkgs = import ./pkgs { pkgs = final; };
          in
          chatmailPkgs
          // {
            opendkim = chatmailPkgs.opendkim-lua;
            dovecot = prev.dovecot.override { withLua = true; };
          };
      };

      perSystem =
        { pkgs, lib, ... }:
        let
          pkgs' = pkgs.extend (
            final: _prev:
            import ./pkgs {
              pkgs = final;
              inherit lib;
            }
          );
          chatmailPkgs = import ./pkgs {
            pkgs = pkgs';
            inherit lib;
          };
        in
        {
          packages = lib.filterAttrs (_: v: lib.isDerivation v) chatmailPkgs;

          formatter = pkgs.nixfmt-rfc-style;

          devShells.default = pkgs.mkShell {
            name = "chatmail-dev";
            buildInputs = with pkgs; [
              nixfmt-rfc-style
              mailutils
              swaks
              mutt
              openssl
              bind
              netcat
              tcpdump
            ];
          };
        };
    };
}
