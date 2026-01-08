# Chatmail Examples

Example NixOS configurations for chatmail deployment.

## Configurations

| File | Description |
|------|-------------|
| `basic.nix` | Quick start with automatic firewall |
| `advanced.nix` | Production with stricter limits, monitoring, and Fail2ban |
| `ipv4-only.nix` | Servers without IPv6 |
| `minimal.nix` | Manual firewall configuration |

## Usage

```nix
{
  inputs.chatmail.url = "github:ViZiD/chatmail-relay-nix";

  outputs = { nixpkgs, chatmail, ... }: {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      modules = [
        chatmail.nixosModules.default
        ./examples/basic.nix
      ];
    };
  };
}
```

## Example Descriptions

### basic.nix

Minimal working configuration with automatic firewall management.

### advanced.nix

Production-ready configuration with:
- Stricter username/password requirements (12+ characters)
- Lower rate limits (30 messages/minute)
- Larger storage (2GB mailbox, 50MB messages)
- Longer retention (90 days)
- Custom DKIM selector
- Passthrough rules for notifications
- mtail metrics enabled
- Fail2ban integration

### ipv4-only.nix

For servers without IPv6 connectivity. Sets both `networking.enableIPv6 = false` and `services.chatmail.disableIpv6 = true`.

### minimal.nix

Shows manual firewall configuration instead of `openFirewall = true`.

## Documentation

See **[DEPLOYMENT.md](../DEPLOYMENT.md)** for:

- Complete DNS configuration
- Post-deployment verification
- Troubleshooting guide
- Service paths and ports
