{ lib }:
let
  inherit (lib) mkDefault mkIf mkMerge;
in
{
  commonHardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    UMask = "0077";
  };
  networkHardening = self: self.commonHardening;
  unixSocketHardening = self: self.commonHardening;
  fullNetworkHardening = self: self.commonHardening;
  mkChatmailService =
    {
      cfg,
      description,
      execStart,
      user ? cfg.user,
      group ? cfg.group,
      hardeningType ? "network", # "network", "unix", "full", "none"
      extraServiceConfig ? { },
      extraUnitConfig ? { },
      readWritePaths ? [ ],
      runtimeDirectory ? null,
      stateDirectory ? null,
    }:
    let
      self = import ./lib.nix { inherit lib; };
      baseHardening =
        if hardeningType == "network" then
          self.networkHardening self
        else if hardeningType == "unix" then
          self.unixSocketHardening self
        else if hardeningType == "full" then
          self.fullNetworkHardening self
        else if hardeningType == "none" then
          { }
        else
          self.commonHardening;
    in
    {
      inherit description;
      after = [ "network.target" "systemd-tmpfiles-setup.service" ] ++ (extraUnitConfig.after or [ ]);
      wantedBy = extraUnitConfig.wantedBy or [ "multi-user.target" ];
      wants = extraUnitConfig.wants or [ ];
      before = extraUnitConfig.before or [ ];
      requires = extraUnitConfig.requires or [ ];
      serviceConfig = mkMerge [
        baseHardening
        {
          Type = "simple";
          User = user;
          Group = group;
          ExecStart = execStart;
          Restart = mkDefault "always";
          RestartSec = mkDefault "30s";
        }
        (mkIf (readWritePaths != [ ]) { ReadWritePaths = readWritePaths; })
        (mkIf (runtimeDirectory != null) {
          RuntimeDirectory = runtimeDirectory;
          RuntimeDirectoryMode = "0755";
        })
        (mkIf (stateDirectory != null) {
          StateDirectory = stateDirectory;
          StateDirectoryMode = "0750";
        })
        extraServiceConfig
      ];
    };
  mkOneshotService =
    {
      cfg,
      description,
      script,
      user ? "root",
      group ? "root",
      extraServiceConfig ? { },
      extraUnitConfig ? { },
    }:
    {
      inherit description;
      wantedBy = extraUnitConfig.wantedBy or [ "multi-user.target" ];
      before = extraUnitConfig.before or [ ];
      after = extraUnitConfig.after or [ ];
      serviceConfig = mkMerge [
        {
          Type = "oneshot";
          RemainAfterExit = true;
          User = user;
          Group = group;
        }
        extraServiceConfig
      ];
      inherit script;
    };
  mkTimerService =
    {
      cfg,
      description,
      execStart ? null,
      script ? null,
      user ? cfg.user,
      group ? cfg.group,
      onCalendar,
      persistent ? true,
      hardeningType ? "none",
      extraServiceConfig ? { },
      readWritePaths ? [ ],
    }:
    let
      self = import ./lib.nix { inherit lib; };
      baseHardening =
        if hardeningType == "network" then
          self.networkHardening self
        else if hardeningType == "unix" then
          self.unixSocketHardening self
        else if hardeningType == "full" then
          self.fullNetworkHardening self
        else if hardeningType == "none" then
          { }
        else
          self.commonHardening;
    in
    {
      service = {
        inherit description;
        serviceConfig = mkMerge [
          baseHardening
          {
            Type = "oneshot";
            User = user;
            Group = group;
          }
          (mkIf (execStart != null) { ExecStart = execStart; })
          (mkIf (readWritePaths != [ ]) { ReadWritePaths = readWritePaths; })
          extraServiceConfig
        ];
      } // (mkIf (script != null) { inherit script; });
      timer = {
        description = "Timer for ${description}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = onCalendar;
          Persistent = persistent;
        };
      };
    };
}
