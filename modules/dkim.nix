# NOTE: We don't use services.opendkim from nixpkgs because it always passes
# -k (KeyFile) and -s (Selector) command-line arguments, which conflicts with
# our KeyTable/SigningTable config file approach needed for Lua policy scripts.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    escapeShellArgs
    mkIf
    optional
    ;
  cfg = config.services.chatmail;
  dkimDir = "/var/lib/dkim";
  dkimKeyFile =
    if cfg.dkim.privateKeyFile != null
    then cfg.dkim.privateKeyFile
    else "${dkimDir}/${cfg.dkim.selector}.private";
  dkimTxtFile = "${dkimDir}/${cfg.dkim.selector}.txt";
  socketPath = "/var/lib/postfix/queue/opendkim/opendkim.sock";
  dkimTableFormat = pkgs.formats.keyValue {
    mkKeyValue = key: value: "${key} ${value}";
  };
  signingTableFile = dkimTableFormat.generate "signing-table" {
    "*@${cfg.domain}" = "${cfg.dkim.selector}._domainkey.${cfg.domain}";
  };
  keyTableFile = dkimTableFormat.generate "key-table" {
    "${cfg.dkim.selector}._domainkey.${cfg.domain}" = "${cfg.domain}:${cfg.dkim.selector}:${dkimKeyFile}";
  };
  screenLuaScript = pkgs.writeText "screen.lua" ''
    from_domain = odkim.get_fromdomain(ctx)
    if from_domain == nil then
      return nil
    end
    n = odkim.get_sigcount(ctx)
    if n == nil then
      return nil
    end
    for i = 1, n do
      sig = odkim.get_sighandle(ctx, i - 1)
      sig_domain = odkim.sig_getdomain(sig)
      if from_domain ~= sig_domain then
        odkim.sig_ignore(sig)
      end
    end
    return nil
  '';
  finalLuaScript = pkgs.writeText "final.lua" ''
    mtaname = odkim.get_mtasymbol(ctx, "{daemon_name}")
    if mtaname == "ORIGINATING" then
      -- Outgoing message will be signed,
      -- no need to look for signatures.
      return nil
    end
    nsigs = odkim.get_sigcount(ctx)
    if nsigs == nil then
      return nil
    end
    local valid = false
    local error_msg = "No valid DKIM signature found."
    for i = 1, nsigs do
      sig = odkim.get_sighandle(ctx, i - 1)
      sigres = odkim.sig_result(sig)
      -- All signatures that do not correspond to From:
      -- were ignored in screen.lua and return sigres -1.
      --
      -- Any valid signature that was not ignored like this
      -- means the message is acceptable.
      if sigres == 0 then
        valid = true
      else
        error_msg = "DKIM signature is invalid, error code " .. tostring(sigres) .. ", search https://github.com/trusteddomainproject/OpenDKIM/blob/master/libopendkim/dkim.h#L108"
      end
    end
    if valid then
      -- Strip all DKIM-Signature headers after successful validation
      -- Delete in reverse order to avoid index shifting.
      for i = nsigs, 1, -1 do
        odkim.del_header(ctx, "DKIM-Signature", i)
      end
    else
      odkim.set_reply(ctx, "554", "5.7.1", error_msg)
      odkim.set_result(ctx, SMFIS_REJECT)
    end
    return nil
  '';
  opendkimConf = pkgs.writeText "opendkim.conf" ''
    Mode sv
    SubDomains no
    Canonicalization relaxed/simple
    Domain csl:${cfg.domain}
    SigningTable refile:${signingTableFile}
    KeyTable ${keyTableFile}
    Socket local:${socketPath}
    On-BadSignature reject
    On-KeyNotFound reject
    On-NoSignature reject
    DNSTimeout 60
    ScreenPolicyScript ${screenLuaScript}
    FinalPolicyScript ${finalLuaScript}
    SignHeaders *,+autocrypt,+content-type
    OversignHeaders ${concatStringsSep "," [
      "from"
      "reply-to"
      "subject"
      "date"
      "to"
      "cc"
      "resent-date"
      "resent-from"
      "resent-sender"
      "resent-to"
      "resent-cc"
      "in-reply-to"
      "references"
      "list-id"
      "list-help"
      "list-unsubscribe"
      "list-subscribe"
      "list-post"
      "list-owner"
      "list-archive"
      "autocrypt"
    ]}
    MTA ORIGINATING
    InternalHosts -
    Syslog yes
    SyslogSuccess yes
    UMask 007
  '';
in
{
  disabledModules = [ "services/mail/opendkim.nix" ];
  config = mkIf (cfg.enable && cfg.dkim.enable) {
    users.users.opendkim = {
      group = "opendkim";
      uid = config.ids.uids.opendkim;
    };
    users.groups.opendkim = {
      gid = config.ids.gids.opendkim;
    };
    environment.systemPackages = [ pkgs.opendkim ];
    systemd.services.opendkim = {
      description = "OpenDKIM signing and verification daemon";
      after = [
        "network.target"
        "postfix-setup.service"
      ];
      requires = [ "postfix-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        mkdir -p ${dkimDir}
        ${
          if cfg.dkim.privateKeyFile != null
          then ''
            if [ ! -f ${cfg.dkim.privateKeyFile} ]; then
              echo "ERROR: DKIM private key file not found: ${cfg.dkim.privateKeyFile}"
              echo "Please ensure the secret is deployed before starting opendkim."
              exit 1
            fi
            echo "Using external DKIM key: ${cfg.dkim.privateKeyFile}"
          ''
          else ''
            if [ ! -f ${dkimKeyFile} ]; then
              echo "Generating DKIM key for selector '${cfg.dkim.selector}'..."
              ${pkgs.opendkim}/bin/opendkim-genkey \
                -b ${toString cfg.dkim.keyBits} \
                -d ${cfg.domain} \
                -s ${cfg.dkim.selector} \
                -D ${dkimDir}
              mv ${dkimDir}/${cfg.dkim.selector}.private ${dkimKeyFile}
              mv ${dkimDir}/${cfg.dkim.selector}.txt ${dkimTxtFile}
              chown opendkim:opendkim ${dkimKeyFile}
              chmod 600 ${dkimKeyFile}
              chown opendkim:opendkim ${dkimTxtFile}
              chmod 644 ${dkimTxtFile}
              echo "DKIM key generated successfully."
              echo "DNS TXT record content:"
              cat ${dkimTxtFile}
            else
              echo "DKIM key already exists at ${dkimKeyFile}"
            fi
          ''
        }
      '';

      serviceConfig = {
        ExecStart = "${pkgs.opendkim}/bin/opendkim -f -l -x ${opendkimConf}";
        User = "opendkim";
        Group = "opendkim";
        StateDirectory = "opendkim";
        StateDirectoryMode = "0700";
        ReadWritePaths = [
          dkimDir
          "/var/lib/postfix/queue/opendkim"
        ];
        RuntimeMaxSec = "1d";
        Restart = "always";
        RestartSec = "30s";
        AmbientCapabilities = [ ];
        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateMounts = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
    systemd.tmpfiles.rules = [
      "d ${dkimDir} 0750 opendkim opendkim -"
      "d /var/lib/postfix/queue/opendkim 0750 opendkim postfix -"
    ];
    users.users.postfix.extraGroups = [ "opendkim" ];

    assertions = [
      {
        assertion = cfg.dkim.privateKeyFile == null || lib.hasPrefix "/" cfg.dkim.privateKeyFile;
        message = "services.chatmail.dkim.privateKeyFile must be an absolute path";
      }
    ];

    warnings =
      optional (cfg.dkim.keyBits < 2048)
        "DKIM key size ${toString cfg.dkim.keyBits} bits is less than recommended 2048 bits"
      ++ optional (cfg.dkim.privateKeyFile != null && lib.hasPrefix "/nix/store" cfg.dkim.privateKeyFile)
        "DKIM private key is stored in Nix store (world-readable). Use sops-nix or agenix for secure key management.";
  };
}
