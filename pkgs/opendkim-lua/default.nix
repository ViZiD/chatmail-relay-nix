{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  libbsd,
  openssl,
  libmilter,
  autoreconfHook,
  perl,
  makeWrapper,
  unbound,
  lua5_1,
}:

stdenv.mkDerivation rec {
  pname = "opendkim";
  version = "2.11.0-Beta2";

  src = fetchFromGitHub {
    owner = "trusteddomainproject";
    repo = "OpenDKIM";
    rev = "rel-opendkim-${lib.replaceStrings [ "." ] [ "-" ] version}";
    sha256 = "0nx3in8sa6xna4vfacj8g60hfzk61jpj2ldag80xzxip9c3rd2pw";
  };

  configureFlags = [
    "--with-milter=${libmilter}"
    "--with-lua=${lua5_1}"
    "ac_cv_func_malloc_0_nonnull=yes"
    "ac_cv_func_realloc_0_nonnull=yes"
  ] ++ lib.optional stdenv.hostPlatform.isDarwin "--with-unbound=${unbound}";

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    libbsd
    openssl
    libmilter
    perl
    lua5_1
  ] ++ lib.optional stdenv.hostPlatform.isDarwin unbound;

  postInstall = ''
    wrapProgram $out/sbin/opendkim-genkey \
      --prefix PATH : ${openssl.bin}/bin
  '';

  meta = {
    description = "OpenDKIM with Lua scripting support for chatmail";
    homepage = "http://www.opendkim.org/";
    maintainers = [ ];
    license = lib.licenses.bsd3;
    platforms = lib.platforms.unix;
  };
}
