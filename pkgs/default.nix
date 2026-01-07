{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:
let
  callPackage = pkgs.callPackage;
in
{
  crypt-r = callPackage ./crypt-r { };
  chatmaild = callPackage ./chatmaild { };
  chatmail-turn = callPackage ./chatmail-turn { };
  chatmail-www = callPackage ./chatmail-www { };
  opendkim-lua = callPackage ./opendkim-lua { };
}
