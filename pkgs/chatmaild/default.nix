{
  lib,
  python3,
  fetchFromGitHub,
  makeWrapper,
  crypt-r,
}:

python3.pkgs.buildPythonApplication {
  pname = "chatmaild";
  version = "0.3";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "chatmail";
    repo = "relay";
    rev = "0e7ab96dc8fd8f6ac6d3a413c4fa0c0b21f2f9f5";
    hash = "sha256-thBFWMJqhsADY+AhODyWCoGQBHq5BA+5UD2TIrYnStc=";
  };

  sourceRoot = "source/chatmaild";

  nativeBuildInputs = [ makeWrapper ];

  build-system = with python3.pkgs; [ setuptools ];

  postPatch = ''
    substituteInPlace src/chatmaild/newemail.py \
      --replace-fail \
        'import json' \
        'import json
import os' \
      --replace-fail \
        'CONFIG_PATH = "/usr/local/lib/chatmaild/chatmail.ini"' \
        'CONFIG_PATH = os.environ.get("CHATMAIL_INI", "/var/lib/chatmail/chatmail.ini")'
  '';

  dependencies = with python3.pkgs; [
    aiosmtpd
    iniconfig
    filelock
    requests
    deltachat-rpc-client
    crypt-r
  ];

  pythonRemoveDeps = [ "deltachat-rpc-server" ];

  doCheck = false;

  postInstall = ''
    makeWrapper ${python3.interpreter} $out/bin/newemail \
      --add-flags "-m chatmaild.newemail" \
      --prefix PYTHONPATH : "$PYTHONPATH"
  '';

  pythonImportsCheck = [ "chatmaild" ];

  meta = {
    description = "Chatmail relay server - lightweight email server for Delta Chat";
    homepage = "https://github.com/deltachat/chatmail";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "filtermail";
  };
}
