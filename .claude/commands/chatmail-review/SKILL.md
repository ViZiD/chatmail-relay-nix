---
name: chatmail-review
description: Review NixOS chatmail modules for compatibility with upstream relay and nixpkgs. Use when user wants to audit modules, check for issues, or verify implementation correctness. Explores the ENTIRE relay project. (project)
---

# Chatmail Review

Review NixOS modules for compatibility with upstream relay and nixpkgs.

## When to use

- User asks to review/audit modules
- User asks to check compatibility
- User asks to verify implementation
- User mentions "check", "audit", "compatibility", "correctness"

## Arguments

This skill accepts optional directory arguments:

| Argument | Description | Default |
|----------|-------------|---------|
| `--relay PATH` | Path to relay repository | `../forks/relay` (relative to project) |
| `--nixpkgs PATH` | Path to nixpkgs repository | `../forks/nixpkgs` (relative to project) |

Example usage:
```
/chatmail-review
/chatmail-review --relay ~/projects/relay --nixpkgs ~/nixpkgs
```

## Source paths

| Variable | Default | Description |
|----------|---------|-------------|
| `$RELAY_PATH` | `../forks/relay` relative to project | Upstream relay repository |
| `$PROJECT_PATH` | Current working directory | This project root |
| `$NIXPKGS_PATH` | `../forks/nixpkgs` or system nixpkgs | nixpkgs for API reference |

## CRITICAL: Update sources first

**ALWAYS pull latest changes before any review work.**

### Step 0: Update relay repository

```bash
cd "$RELAY_PATH" && git pull origin main
cd "$PROJECT_PATH"
```

## CRITICAL: Full exploration required

**NEVER review based on assumptions. ALWAYS explore the ENTIRE relay project first.**

## Review procedure

### Phase 1: Discover relay project

```bash
tree -a "$RELAY_PATH" -I '.git|__pycache__|*.pyc|.mypy_cache|node_modules|.tox'

find "$RELAY_PATH" -type f \( \
  -name "*.conf*" -o -name "*.ini*" -o -name "*.j2" -o \
  -name "*.toml" -o -name "*.yaml" -o -name "*.yml" -o \
  -name "*.lua" -o -name "*.xml" \
\) 2>/dev/null

find "$RELAY_PATH" -type f \( -name "*.service*" -o -name "*.timer*" \) 2>/dev/null

find "$RELAY_PATH" -type f -name "*.py" -path "*/src/*" 2>/dev/null

find "$RELAY_PATH" -type f -name "deployer*.py" 2>/dev/null
```

### Phase 2: Discover NixOS implementation

```bash
ls -la "$PROJECT_PATH/modules/"
ls -la "$PROJECT_PATH/pkgs/"
find "$PROJECT_PATH/pkgs/" -name "*.nix" -type f
```

### Phase 3: Compare modules

For EACH file found in relay:

1. **Identify what it configures**
2. **Find corresponding NixOS module**
3. **Compare line by line**
4. **Check for missing features**

### Phase 4: Compare packages

For EACH package in `pkgs/`:

1. **Check parameter names match relay conventions**
2. **Verify build scripts match relay's approach**
3. **Check version/source matches upstream relay**

```bash
diff -u "$RELAY_PATH/www/src/" "$PROJECT_PATH/pkgs/chatmail-www/"
grep -r "version\|rev\|hash" "$PROJECT_PATH/pkgs/chatmaild/"
```

### Phase 5: Check nixpkgs usage

For EACH `services.*` used in our modules:

```bash
find "$NIXPKGS_PATH/nixos/modules/" -name "*.nix" | xargs grep -l "services.SERVICE_NAME"
grep -A 5 "mkOption" "$NIXPKGS_PATH/nixos/modules/services/mail/SERVICE.nix"
```

Verify we're using the correct nixpkgs APIs.

## Review checklist

### Discovery (REQUIRED - don't skip)
- [ ] Explored full relay project structure with `tree`
- [ ] Found ALL config files in relay
- [ ] Found ALL systemd units in relay
- [ ] Found ALL Python modules in relay
- [ ] Found ALL deployer files in relay
- [ ] Listed all our NixOS modules

### Completeness check (relay → NixOS)
- [ ] Every relay config file has corresponding NixOS implementation
- [ ] Every relay systemd unit has corresponding NixOS service
- [ ] Every relay Python module is packaged or referenced
- [ ] Every INI option is in our INI generation
- [ ] Every package in pkgs/ matches relay source/version

### Extra additions check (NixOS → relay)
- [ ] No extra nginx locations that don't exist in relay
- [ ] No extra systemd services not in relay
- [ ] No extra config options not in relay INI template
- [ ] No extra packages not needed by relay
- [ ] Check for deprecated relay components (look for `present=False` in deployers.py)

### Correctness check
- [ ] Config values match relay defaults
- [ ] Systemd unit settings match (User, ExecStart, dependencies)
- [ ] Ports and paths match relay
- [ ] Security settings match relay

### Packages check
- [ ] Package parameters match relay conventions (domain, not mailDomain)
- [ ] Build scripts follow relay's approach
- [ ] Source revisions are up to date with relay
- [ ] chatmail-www templates match relay/www/src/

### nixpkgs compliance
- [ ] Using `services.dovecot2` correctly
- [ ] Using `services.postfix` correctly
- [ ] Using `services.nginx` correctly
- [ ] Using `services.opendkim` correctly
- [ ] Using `security.acme` correctly
- [ ] Using `services.unbound` correctly

### NixOS-native vs Debian workarounds
- [ ] Using NixOS options instead of relay's Debian-specific workarounds
- [ ] Not copying manual environment variables that NixOS handles natively
- [ ] Checked each relay workaround against NixOS native solution table below

### Integration check
- [ ] Service dependencies are correct
- [ ] Socket paths match between services
- [ ] Users/groups are consistent
- [ ] ACME certificates used by all TLS services

## NixOS-native vs Debian workarounds

Relay is designed for Debian/pyinfra deployment. NixOS has native declarative solutions for many things that Debian requires workarounds for.

### Principle

**Don't copy Debian-specific patterns. Find the NixOS-native way.**

### How to identify Debian workarounds in relay

```bash
grep -E "Environment=" "$RELAY_PATH/cmdeploy/src/cmdeploy/service/"*.service*
grep -E "server\.shell|run_shell" "$RELAY_PATH/cmdeploy/src/cmdeploy/deployers.py"
grep -E "apt\.|packages\." "$RELAY_PATH/cmdeploy/src/cmdeploy/deployers.py"
find "$RELAY_PATH" -name "*.cron*" -o -name "*cron*.j2"
grep -E "files\.put|files\.template" "$RELAY_PATH/cmdeploy/src/cmdeploy/deployers.py"
```

### Decision process

For each Debian pattern found:

1. **Identify the intent** - what is relay trying to achieve?
2. **Search nixpkgs for native support**:
   ```bash
   find "$NIXPKGS_PATH/nixos/modules/" -name "*.nix" | xargs grep -l "feature"
   ```
3. **If NixOS has native option** → use it instead of copying Debian approach
4. **If no native option** → implement following relay's approach

### Common patterns

| Relay Pattern | Check NixOS For |
|---------------|-----------------|
| `Environment=VAR=...` in systemd | Global NixOS option that sets this |
| `/etc/cron.d/*` files | `systemd.timers` |
| `acmetool` / certbot scripts | `security.acme` module |
| `apt install package` | Service module dependencies |
| `useradd`/`groupadd` | `users.users`/`users.groups` |
| `iptables` commands | `networking.firewall` |
| Template to `/etc/file` | Service's `configFile` or `extraConfig` |

### Verification

Before adding any relay systemd setting to NixOS:

```bash
grep -r "SETTING_NAME" "$NIXPKGS_PATH/nixos/modules/"
grep -A5 "mkOption" "$NIXPKGS_PATH/nixos/modules/services/mail/SERVICE.nix"
```

## How to find discrepancies

### INI options

```bash
grep -E "^[a-z_]+ ?=" "$RELAY_PATH/chatmaild/src/chatmaild/ini/chatmail.ini.f"
grep -E "params\[|params\.get" "$RELAY_PATH/chatmaild/src/chatmaild/config.py"
grep -E "[a-z_]+ =" "$PROJECT_PATH/modules/chatmaild.nix"
```

### Systemd services

```bash
cat "$RELAY_PATH/cmdeploy/src/cmdeploy/service/"*.service*
grep -A 20 "systemd.services" "$PROJECT_PATH/modules/"*.nix
```

### Config values

```bash
grep -r "setting_name" "$RELAY_PATH" --include="*.j2" --include="*.conf*" --include="*.py"
grep -r "setting_name" "$PROJECT_PATH/modules/"
```

## Output format

```markdown
## Review Report

### Exploration Summary
- Files examined in relay: X
- Config files found: X
- Systemd units found: X
- Python modules found: X

### Completeness: X%

| Relay Component | NixOS Module | Status |
|-----------------|--------------|--------|
| component | module.nix | ✅/⚠️/❌ |

### Issues Found

#### Critical
1. **[file:line]** Description
   - Relay: `value`
   - NixOS: `value`
   - Impact: ...

#### Warnings
1. ...

#### Suggestions
1. ...

### nixpkgs API Usage
- services.dovecot2: ✅/❌
- services.postfix: ✅/❌
- ...

### Recommendations
1. ...
```

## How to find extra additions

### Check for extra nginx locations

```bash
grep -E "location\s+/" "$RELAY_PATH/cmdeploy/src/cmdeploy/nginx/nginx.conf.j2"
grep -E '"/[^"]*"\s*=' "$PROJECT_PATH/modules/nginx.nix"
```

### Check for deprecated components in relay

```bash
grep -B2 -A2 "present=False" "$RELAY_PATH/cmdeploy/src/cmdeploy/deployers.py"
grep -B2 -A2 "running=False\|enabled=False" "$RELAY_PATH/cmdeploy/src/cmdeploy/deployers.py"
```

### Check for features NOT in relay

```bash
grep -r "feature_name" "$RELAY_PATH" --include="*.j2" --include="*.conf*" --include="*.py"
```

## Common issues to check

### Extra addition (not in relay)
- Feature exists in NixOS but grep finds nothing in relay
- Remove any feature not found in relay source

### Deprecated component
- Relay has `present=False` or `running=False` for component
- Examples of deprecated components (NOT to be implemented):
  - `mta-sts-daemon` - removed from relay (present=False)
  - `echobot.service` - disabled in relay (running=False, enabled=False)
  - `rspamd` - removed from relay (present=False)
  - `doveauth-dictproxy.service` - legacy, replaced by doveauth.service

### Missing INI option
- Check `chatmail.ini.f` vs `chatmaild.nix` INI generation

### Wrong default value
- Compare relay template defaults with NixOS option defaults

### Missing systemd setting
- Check relay `.service.f` files for RuntimeMaxSec, Restart, etc.

### Wrong service dependency
- Check relay deployers for service ordering

### Missing config file
- Check relay for files we might not have implemented

### Incorrect nixpkgs usage
- Check nixpkgs module source for correct option types

### Package out of sync
- Compare pkgs/chatmail-www rev with relay latest commit
- Check pkgs/chatmaild version matches relay

### Path/value mismatch between services
- INI options with `params.get()` defaults may differ from NixOS values
- Paths used by multiple services (chatmaild + dovecot/postfix) must match
- Socket paths must be identical between communicating services

## Critical: INI Options with Relay Defaults

### Rule

```
If relay has: params.get("option", default_value)
And NixOS uses: different_value
Then: MUST set option in INI
```

### How to verify any option

```bash
grep -E "params\.get\(\"OPTION\"" "$RELAY_PATH/chatmaild/src/chatmaild/config.py"
grep -r "config\.OPTION\|self\.OPTION" "$RELAY_PATH/chatmaild/src/chatmaild/"*.py
grep "OPTION" "$PROJECT_PATH/modules/chatmaild.nix"
```

### Cross-service path verification

```bash
# For paths shared between chatmaild and nixpkgs services:
# 1. Find INI option in chatmaild.nix
# 2. Find corresponding nixpkgs service option
# 3. Verify they resolve to the same path
```
