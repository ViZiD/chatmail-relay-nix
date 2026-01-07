{
  lib,
  python3,
  fetchFromGitHub,
  libxcrypt,
}:

python3.pkgs.buildPythonPackage rec {
  pname = "crypt-r";
  version = "3.13.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "fedora-python";
    repo = "crypt_r";
    rev = "v${version}";
    hash = "sha256-Ar8tilj2WKr+v+DjZCs4aGCmc7qABIeEZTuX63SJ0aQ=";
  };

  build-system = with python3.pkgs; [ setuptools ];

  buildInputs = [ libxcrypt ];

  pythonImportsCheck = [ "crypt_r" ];

  meta = {
    description = "Fork of the crypt module removed from Python 3.13";
    homepage = "https://github.com/fedora-python/crypt_r";
    license = lib.licenses.psfl;
    maintainers = with lib.maintainers; [ ];
  };
}
