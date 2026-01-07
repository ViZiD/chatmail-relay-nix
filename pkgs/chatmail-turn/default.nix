{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "chatmail-turn";
  version = "0.3";

  src = fetchFromGitHub {
    owner = "chatmail";
    repo = "chatmail-turn";
    rev = "7f7cc0c0f24108dee6acc62e00694512bd3fe399";
    hash = "sha256-NimIeiiGefxTq8r2XX8Ifbj1VZo7NQ+zS97fg0puPxo=";
  };

  cargoHash = "sha256-DHlc9O/NjOeHuVwrhcIQQZqEqApmS+Wbd8e0CEpORus=";

  meta = {
    description = "TURN server for chatmail with integrated credential generation";
    homepage = "https://github.com/chatmail/chatmail-turn";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "chatmail-turn";
  };
}
