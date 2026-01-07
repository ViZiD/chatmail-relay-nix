{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    optionalString
    ;
  cfg = config.services.chatmail;
  keyValueFormat = pkgs.formats.keyValue {
    mkKeyValue = key: value: "${key} = ${value}";
  };
  authConfFile = keyValueFormat.generate "auth.conf" {
    uri = "proxy:/run/doveauth/doveauth.socket:auth";
    iterate_disable = "no";
    iterate_prefix = "userdb/";
    default_pass_scheme = "plain";
    password_key = ''passdb/%Ew"%Eu'';
    user_key = "userdb/%Eu";
  };
  pushNotificationScript = pkgs.writeText "push_notification.lua" ''
    function dovecot_lua_notify_begin_txn(user)
      return user
    end
    function dovecot_lua_notify_event_message_new(user, event)
      local mbox = user:mailbox(event.mailbox)
      mbox:sync()
      if user.username ~= event.from_address then
        -- Incoming message from another user
        -- Notify metadata server about new message via metadata API
        mbox:metadata_set("/private/messagenew", "")
      end
      mbox:free()
    end
    function dovecot_lua_notify_end_txn(ctx, success)
    end
  '';
in
{
  config = mkIf (cfg.enable && cfg.dovecot.enable) {
    services.dovecot2 = {
      enable = true;
      protocols = cfg.dovecot.protocols;
      mailLocation = "maildir:${cfg.vmailDir}/%u";
      mailUser = "vmail";
      mailGroup = "vmail";
      sslServerCert = "/var/lib/acme/${cfg.domain}/fullchain.pem";
      sslServerKey = "/var/lib/acme/${cfg.domain}/key.pem";
      extraConfig = ''
        ${optionalString cfg.disableIpv6 ''
        listen = *
        ''}
        ${optionalString cfg.debug ''
        auth_verbose = yes
        auth_debug = yes
        auth_debug_passwords = yes
        auth_verbose_passwords = plain
        auth_cache_size = 100M
        mail_debug = yes
        ''}
        imap_capability = +XDELTAPUSH XCHATMAIL
        mail_server_admin = mailto:root@${cfg.domain}
        mail_server_comment = Chatmail server
        default_client_limit = 20000
        mail_cache_max_size = 500K
        ssl = required
        ssl_min_protocol = TLSv1.3
        ssl_prefer_server_ciphers = yes
        mail_uid = vmail
        mail_gid = vmail
        mail_privileged_group = vmail
        ${optionalString (cfg.dovecot.vmailUid != null) ''
        first_valid_uid = ${toString cfg.dovecot.vmailUid}
        last_valid_uid = ${toString cfg.dovecot.vmailUid}
        ''}
        ${optionalString (cfg.dovecot.vmailGid != null) ''
        first_valid_gid = ${toString cfg.dovecot.vmailGid}
        last_valid_gid = ${toString cfg.dovecot.vmailGid}
        ''}
        auth_mechanisms = plain
        auth_failure_delay = 0
        passdb {
          driver = dict
          args = ${authConfFile}
        }
        userdb {
          driver = dict
          args = ${authConfFile}
        }
        mail_plugins = zlib quota
        mail_attribute_dict = proxy:${cfg.metadata.socketPath}:metadata
        protocol imap {
          mail_plugins = $mail_plugins imap_quota last_login ${optionalString cfg.dovecot.imapCompress "imap_zlib"}
          imap_metadata = yes
          mail_max_userip_connections = 20
        }
        protocol lmtp {
          mail_plugins = $mail_plugins mail_lua notify push_notification push_notification_lua
          postmaster_address = postmaster@${cfg.domain}
        }
        plugin {
          last_login_dict = proxy:${cfg.lastlogin.socketPath}:lastlogin
          last_login_precision = s
          zlib_save = gz
          ${optionalString cfg.dovecot.imapCompress ''
          imap_compress_deflate_level = 6
          ''}
          quota = maildir:User quota
          quota_rule = *:storage=${cfg.maxMailboxSize}
          quota_max_mail_size = ${toString cfg.maxMessageSize}
          quota_grace = 0
          push_notification_driver = lua:file=${pushNotificationScript}
        }
        service imap-login {
          service_count = 0
          vsz_limit = 1G
          process_min_avail = 10
          inet_listener imap {
            port = 143
          }
          inet_listener imaps {
            port = 993
            ssl = yes
          }
        }
        service imap {
          process_limit = 50000
        }
        service anvil {
          unix_listener anvil-auth-penalty {
            mode = 0
          }
        }
        service auth-worker {
          user = vmail
        }
        ${optionalString cfg.postfix.enable ''
        service lmtp {
          unix_listener /var/lib/postfix/queue/private/dovecot-lmtp {
            group = postfix
            mode = 0600
            user = postfix
          }
        }
        service auth {
          unix_listener /var/lib/postfix/queue/private/auth {
            mode = 0660
            user = postfix
            group = postfix
          }
        }
        ''}
        namespace inbox {
          inbox = yes
          mailbox Drafts {
            special_use = \Drafts
          }
          mailbox Junk {
            special_use = \Junk
          }
          mailbox Trash {
            special_use = \Trash
          }
          mailbox Sent {
            special_use = \Sent
          }
          mailbox "Sent Messages" {
            special_use = \Sent
          }
        }
        ${optionalString (!cfg.dovecot.imapCompress) ''
        imap_hibernate_timeout = 30s
        service imap {
          unix_listener imap-master {
            user = $default_internal_user
          }
          extra_groups = $default_internal_group
        }
        service imap-hibernate {
          unix_listener imap-hibernate {
            mode = 0660
            group = $default_internal_group
          }
        }
        ''}
        ${optionalString cfg.dovecot.imapRawlog ''
        service postlogin {
          executable = script-login -d rawlog
          unix_listener postlogin {
          }
        }
        service imap {
          executable = imap postlogin
        }
        protocol imap {
          rawlog_dir = %h
        }
        ''}
        log_path = syslog
        syslog_facility = mail
        disable_plaintext_auth = yes
      '';
    };
    environment.etc."dovecot/auth.conf".source = authConfFile;
    environment.systemPackages = with pkgs; [
      dovecot_pigeonhole
    ];
    users.users.dovecot = {
      isSystemUser = true;
      group = "dovecot";
      extraGroups = [ "acme" ];
    };
    users.groups.dovecot = { };
    systemd.services.dovecot = {
      after = [
        "chatmail-doveauth.service"
        "chatmail-metadata.service"
        "chatmail-lastlogin.service"
        "postfix-setup.service"
      ];
      wants = [
        "chatmail-doveauth.service"
        "chatmail-metadata.service"
        "chatmail-lastlogin.service"
        "postfix-setup.service"
      ];
      serviceConfig = {
        SupplementaryGroups = [ cfg.group ];
        Restart = lib.mkForce "always";
        RestartSec = lib.mkForce "30s";
        LimitNOFILE = 65536;
      };
    };
  };
}
