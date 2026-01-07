{ ... }:
{
  services.chatmail = {
    enable = true;
    openFirewall = true;
    domain = "chat.example.org";
    acme.email = "admin@example.org";
    privacyMail = "privacy@example.org";
    privacyPostal = ''
      Example Company Ltd
      123 Main Street
      12345 City, Country
    '';
    privacyPdo = "dpo@example.org";
    privacySupervisor = "State Data Protection Authority";
    usernameMinLength = 12;
    usernameMaxLength = 32;
    passwordMinLength = 12;
    maxUserSendPerMinute = 30;
    maxMessageSize = 52428800;
    maxMailboxSize = "2G";
    deleteMailsAfter = "90";
    deleteLargeAfter = "30";
    inactiveUserDays = 180;
    passthroughSenders = [ "noreply@chat.example.org" ];
    passthroughRecipients = [ "@trusted-partner.org" ];
    dkim.selector = "mail";
    mtail.enable = true;
  };
  services.fail2ban = {
    enable = true;
    jails.dovecot.settings = {
      enabled = true;
      maxretry = 5;
    };
    jails.postfix.settings = {
      enabled = true;
      maxretry = 5;
    };
  };
}
