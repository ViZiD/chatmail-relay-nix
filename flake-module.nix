{
  flake = {
    nixosModules.default = ./modules;
    nixosModules.chatmail = ./modules;
    overlays.default = import ./overlays;
  };
}
