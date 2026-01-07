{ ... }:
{
  services.chatmail = {
    enable = true;
    domain = "chat.example.org";
    acme.email = "admin@example.org";
    privacyMail = "privacy@example.org";
  };
  networking.firewall = {
    allowedTCPPorts = [ 25 80 143 443 465 587 993 3478 ];
    allowedUDPPorts = [ 3478 ];
    allowedUDPPortRanges = [ { from = 49152; to = 65535; } ];
  };
}
