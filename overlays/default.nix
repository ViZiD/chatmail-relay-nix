final: prev:
let
  chatmailPkgs = import ../pkgs { pkgs = final; };
in
chatmailPkgs
// {
  opendkim = chatmailPkgs.opendkim-lua;
  dovecot = prev.dovecot.override { withLua = true; };
}
