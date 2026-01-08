# Chatmail NixOS

> **WARNING**: This project was fully vibe-coded using [Claude Code](https://github.com/anthropics/claude-code). The author bears no responsibility for any issues, damages, or consequences arising from the use of this code. Use at your own risk.

NixOS modules for [chatmail relay](https://github.com/chatmail/relay) - email server for [Delta Chat](https://delta.chat).

## Quick Start

```nix
{
  inputs.chatmail.url = "github:ViZiD/chatmail-relay-nix";

  outputs = { nixpkgs, chatmail, ... }: {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      modules = [
        chatmail.nixosModules.default
        {
          services.chatmail = {
            enable = true;
            openFirewall = true;
            domain = "chat.example.org";
            acme.email = "admin@example.org";
            privacyMail = "privacy@example.org";
          };
        }
      ];
    };
  };
}
```

## Documentation

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Deployment guide
- **[examples/](./examples/)** - Example configurations

## Requirements

- NixOS 24.05+
- Public IP with port 25 open
- Domain with DNS access

## License

WTFPL

## Links

- [Delta Chat](https://delta.chat)
- [Chatmail Relay](https://github.com/chatmail/relay)
