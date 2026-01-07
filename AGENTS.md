# Chatmail NixOS - Agent Instructions

This document provides instructions for AI agents working with the Chatmail NixOS implementation.

## Project Overview

This project is a **NixOS implementation** of the [Delta Chat relay](https://github.com/chatmail/relay) (chatmail server).

### Source Paths

| Variable | Default | Description |
|----------|---------|-------------|
| `$RELAY_PATH` | `../forks/relay` relative to project | Original relay implementation |
| `$NIXPKGS_PATH` | `../forks/nixpkgs` or system nixpkgs | NixOS upstream modules |
| `$PROJECT_PATH` | Current working directory | This project root |

Project structure:
- `$PROJECT_PATH/modules/` - NixOS modules
- `$PROJECT_PATH/pkgs/` - NixOS packages

## Critical Rules

1. **ALWAYS update sources first** - run `git pull origin main` in relay before any work
2. **NEVER deviate from the original relay implementation** - always check relay project for correct behavior
3. **NEVER add features not in relay** - if grep finds nothing in relay, don't add it to NixOS
4. **Check for deprecated components** - relay removes features with `present=False` in deployers.py
5. **Always use nixpkgs modules where available** - prefer upstream `services.*` over custom implementations
6. **Explore the ENTIRE relay project** - don't assume you know all files, always search thoroughly
7. **cmdeploy is reference only** - we don't use pyinfra, but configs are authoritative
8. **Check ALL config files** - relay may have configs in unexpected places

## Before ANY work

```bash
cd "$RELAY_PATH" && git pull origin main
```

## Available Skills

| Skill | Command | Description |
|-------|---------|-------------|
| Sync | `/chatmail-sync` | Synchronize modules with upstream relay |
| Review | `/chatmail-review` | Review modules for compatibility |

### Skill Arguments

Both skills accept optional path arguments:

```
/chatmail-sync --relay /path/to/relay --nixpkgs /path/to/nixpkgs
/chatmail-review --relay ~/projects/relay
```

## Workflow

### Before making changes

1. **Explore relay project thoroughly** - use `find`, `grep`, `tree` to discover all relevant files
2. **Read the actual relay code** - don't rely on assumptions
3. **Check nixpkgs for native support** - always prefer upstream modules
4. **Understand the full picture** - one change may affect multiple modules

### When implementing features

1. Find ALL related files in relay (configs, services, scripts, templates)
2. Check how relay handles edge cases
3. Map to appropriate nixpkgs APIs
4. Maintain exact behavior compatibility
5. Keep pkgs/ in sync with relay source revisions

### After making changes

1. Verify INI generation matches relay format
2. Check systemd services match relay
3. Ensure all dependencies are correct
4. Update package revisions if relay source changed

## Checking for Extra Additions

Before adding ANY feature, verify it exists in relay:

```bash
grep -r "feature_name" "$RELAY_PATH" --include="*.j2" --include="*.conf*" --include="*.py"
```

If empty result → DON'T add it to NixOS.

### Finding deprecated components

```bash
grep -B2 -A2 "present=False" "$RELAY_PATH/cmdeploy/src/cmdeploy/deployers.py"
grep -B2 -A2 "running=False\|enabled=False" "$RELAY_PATH/cmdeploy/src/cmdeploy/deployers.py"
```

### Examples of deprecated features (NOT to be implemented in NixOS)

- `mta-sts-daemon` - removed from relay (present=False in deployers.py)
- `echobot.service` - disabled in relay (running=False, enabled=False in deployers.py)
- `rspamd` - removed from relay (present=False in deployers.py)
- `doveauth-dictproxy.service` - legacy service, replaced by `doveauth.service`

## NixOS-native vs Debian workarounds

Relay is designed for Debian/pyinfra. NixOS has native declarative solutions for many things that Debian requires workarounds for.

**Principle: Don't copy Debian-specific patterns. Find the NixOS-native way.**

### How to identify Debian workarounds

```bash
grep -E "Environment=" "$RELAY_PATH/cmdeploy/src/cmdeploy/service/"*.service*
find "$RELAY_PATH" -name "*.cron*" -o -name "*cron*.j2"
```

### Decision process

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

## Critical: Path and Value Synchronization

### Rule: INI options with relay defaults

When relay's `config.py` has a default value via `params.get("option", default)`:
- If NixOS uses a **different** value → MUST set in INI
- If NixOS uses the **same** value → can omit from INI

### How to check any INI option

```bash
grep -E "params\.get\(\"OPTION_NAME\"" "$RELAY_PATH/chatmaild/src/chatmaild/config.py"
grep -r "config\.OPTION_NAME\|self\.OPTION_NAME" "$RELAY_PATH/chatmaild/src/chatmaild/"*.py
```

Compare relay default with NixOS value. If different → MUST explicitly set in INI.

### General consistency rules

1. **Paths used by multiple services** must match:
   - INI value ↔ nixpkgs service config (dovecot, postfix, etc.)
   - Socket paths between dependent services

2. **Before removing any INI option**, verify:
   - Does relay have a default? (`params.get`)
   - Does NixOS use the same default?
   - Is the option used by other services that might have different paths?

3. **Socket paths** - services communicating via sockets must use identical paths
