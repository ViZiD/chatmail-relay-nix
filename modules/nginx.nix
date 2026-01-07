{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    getExe'
    mkIf
    optional
    optionalString
    ;
  cfg = config.services.chatmail;
  alpnProxyConfig = pkgs.writeText "nginx-stream.conf" ''
    map $ssl_preread_alpn_protocols $proxy {
      default 127.0.0.1:8443;
      ~\bsmtp\b 127.0.0.1:465;
      ~\bimap\b 127.0.0.1:993;
    }
    server {
      listen 443;
      ${optionalString (!cfg.disableIpv6) "listen [::]:443;"}
      ssl_preread on;
      proxy_pass $proxy;
    }
  '';
  autoconfigXml = pkgs.writeText "config-v1.1.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>

    <clientConfig version="1.1">
      <emailProvider id="${cfg.domain}">
        <domain>${cfg.domain}</domain>
        <displayName>${cfg.domain} chatmail</displayName>
        <displayShortName>${cfg.domain}</displayShortName>
        <incomingServer type="imap">
          <hostname>${cfg.domain}</hostname>
          <port>993</port>
          <socketType>SSL</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <incomingServer type="imap">
          <hostname>${cfg.domain}</hostname>
          <port>143</port>
          <socketType>STARTTLS</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <incomingServer type="imap">
          <hostname>${cfg.domain}</hostname>
          <port>443</port>
          <socketType>SSL</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <outgoingServer type="smtp">
          <hostname>${cfg.domain}</hostname>
          <port>465</port>
          <socketType>SSL</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </outgoingServer>
        <outgoingServer type="smtp">
          <hostname>${cfg.domain}</hostname>
          <port>587</port>
          <socketType>STARTTLS</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </outgoingServer>
        <outgoingServer type="smtp">
          <hostname>${cfg.domain}</hostname>
          <port>443</port>
          <socketType>SSL</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </outgoingServer>
      </emailProvider>
    </clientConfig>
  '';
  mtaStsTxt = pkgs.writeText "mta-sts.txt" ''
    version: STSv1
    mode: enforce
    mx: ${cfg.domain}
    max_age: 2419200
  '';
in
{
  config = mkIf (cfg.enable && cfg.nginx.enable) {
    services.fcgiwrap.instances.chatmail = mkIf cfg.newAccount.enable {
      process.user = "nginx";
      process.group = "nginx";
      socket = {
        user = "nginx";
        group = "nginx";
        mode = "0600";
      };
    };
    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      serverNamesHashBucketSize = 64;
      appendConfig = ''
        worker_rlimit_nofile 2048;
      '';
      eventsConfig = ''
        worker_connections 2048;
      '';
      streamConfig = mkIf cfg.nginx.enableALPN ''
        include ${alpnProxyConfig};
      '';
      virtualHosts = {
        "${cfg.domain}" = {
          forceSSL = true;
          listen =
            if cfg.nginx.enableALPN then
              [
                {
                  addr = "127.0.0.1";
                  port = 8443;
                  ssl = true;
                }
              ]
            else
              [
                {
                  addr = "0.0.0.0";
                  port = 443;
                  ssl = true;
                }
              ]
              ++ optional (!cfg.disableIpv6) {
                addr = "[::]";
                port = 443;
                ssl = true;
              };
          root = cfg.www.root;
          locations = {
            "/" = {
              index = "index.html";
              tryFiles = "$uri $uri/ =404";
            };
            "= /metrics" = mkIf cfg.metrics.enable {
              alias = "${cfg.metrics.outputDir}/metrics.txt";
              extraConfig = ''
                default_type text/plain;
                add_header Content-Type text/plain;
              '';
            };
            "= /.well-known/autoconfig/mail/config-v1.1.xml" = {
              alias = autoconfigXml;
              extraConfig = ''
                default_type application/xml;
              '';
            };
            "/generate_204" = mkIf cfg.irohRelay.enable {
              proxyPass = "http://127.0.0.1:${toString cfg.irohRelay.port}";
              extraConfig = ''
                proxy_http_version 1.1;
              '';
            };
            "/new" = mkIf cfg.newAccount.enable {
              extraConfig = ''
                if ($request_method = GET) {
                  return 301 dcaccount:https://${cfg.domain}/new;
                }
                fastcgi_pass unix:/run/fcgiwrap-chatmail.sock;
                include ${config.services.nginx.package}/conf/fastcgi_params;
                fastcgi_param SCRIPT_FILENAME ${getExe' cfg.package "newemail"};
                fastcgi_param CHATMAIL_INI ${cfg.configFile};
              '';
            };
            "/cgi-bin/newemail.py" = mkIf cfg.newAccount.enable {
              extraConfig = ''
                if ($request_method = GET) {
                  return 301 dcaccount:https://${cfg.domain}/new;
                }
                fastcgi_pass unix:/run/fcgiwrap-chatmail.sock;
                include ${config.services.nginx.package}/conf/fastcgi_params;
                fastcgi_param SCRIPT_FILENAME ${getExe' cfg.package "newemail"};
                fastcgi_param CHATMAIL_INI ${cfg.configFile};
              '';
            };
          };
        };
        "www.${cfg.domain}" = {
          listen =
            if cfg.nginx.enableALPN then
              [
                {
                  addr = "127.0.0.1";
                  port = 8443;
                  ssl = true;
                }
              ]
            else
              [
                {
                  addr = "0.0.0.0";
                  port = 443;
                  ssl = true;
                }
              ]
              ++ optional (!cfg.disableIpv6) {
                addr = "[::]";
                port = 443;
                ssl = true;
              };
          addSSL = true;
          useACMEHost = cfg.domain;
          globalRedirect = cfg.domain;
        };
        "mta-sts.${cfg.domain}" = mkIf cfg.acme.enable {
          listen =
            if cfg.nginx.enableALPN then
              [
                {
                  addr = "127.0.0.1";
                  port = 8443;
                  ssl = true;
                }
              ]
            else
              [
                {
                  addr = "0.0.0.0";
                  port = 443;
                  ssl = true;
                }
              ]
              ++ optional (!cfg.disableIpv6) {
                addr = "[::]";
                port = 443;
                ssl = true;
              };
          addSSL = true;
          useACMEHost = cfg.domain;
          locations."= /.well-known/mta-sts.txt" = {
            alias = mtaStsTxt;
            extraConfig = ''
              default_type text/plain;
            '';
          };
          locations."/" = {
            return = "301 https://${cfg.domain}$request_uri";
          };
        };
      };
    };
    users.users.nginx.extraGroups = [ "acme" ];
  };
}
