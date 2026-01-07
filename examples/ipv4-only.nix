{ ... }:
{
  networking.enableIPv6 = false;

  services.chatmail = {
    enable = true;
    openFirewall = true;
    domain = "chat.example.org";
    acme.email = "admin@example.org";
    privacyMail = "privacy@example.org";
    disableIpv6 = true;
  };
}
