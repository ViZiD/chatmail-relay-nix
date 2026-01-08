# Chatmail NixOS Deployment Guide

This guide covers deploying a chatmail relay server using NixOS.

## Prerequisites

- NixOS 24.05 or later
- Public IP address (IPv4 required, IPv6 recommended)
- Domain with DNS access
- Port 25 open (not blocked by ISP)

## DNS Configuration

Configure these DNS records before deployment. Replace `chat.example.org` with your domain and use your server's IP addresses.

### Required Records

```zone
; A/AAAA records (use your server's IP addresses)
chat.example.org.                   A     YOUR_IPV4_ADDRESS
chat.example.org.                   AAAA  YOUR_IPV6_ADDRESS

; Mail exchange
chat.example.org.                   MX 10 chat.example.org.

; MTA-STS (generate id with: date +%Y%m%d%H%M)
_mta-sts.chat.example.org.          TXT "v=STSv1; id=202501061200"
mta-sts.chat.example.org.           CNAME chat.example.org.

; WWW redirect
www.chat.example.org.               CNAME chat.example.org.
```

### Security Records

```zone
; SPF - authorize only this server to send mail
chat.example.org.                   TXT "v=spf1 a ~all"

; DMARC - strict policy, reject failures
_dmarc.chat.example.org.            TXT "v=DMARC1;p=reject;adkim=s;aspf=s"

; ADSP - discardable unsigned mail
_adsp._domainkey.chat.example.org.  TXT "dkim=discardable"
```

### Service Discovery (SRV Records)

```zone
; Mail client autoconfiguration
_submission._tcp.chat.example.org.  SRV 0 1 587 chat.example.org.
_submissions._tcp.chat.example.org. SRV 0 1 465 chat.example.org.
_imap._tcp.chat.example.org.        SRV 0 1 143 chat.example.org.
_imaps._tcp.chat.example.org.       SRV 0 1 993 chat.example.org.
```

### DKIM Record (after deployment)

DKIM key is generated on first start. Retrieve it with:

```bash
cat /var/lib/dkim/opendkim.txt
```

Add to DNS:

```zone
opendkim._domainkey.chat.example.org. TXT "v=DKIM1; k=rsa; p=YOUR_PUBLIC_KEY"
```

**Note:** You can use your own DKIM key via sops-nix or agenix:

```nix
{
  sops.secrets.dkim-private-key = {
    owner = "opendkim";
    group = "opendkim";
    mode = "0400";
  };

  services.chatmail.dkim.privateKeyFile = config.sops.secrets.dkim-private-key.path;
}
```

### Optional: CAA Record

Restrict certificate issuance to Let's Encrypt:

```zone
chat.example.org.                   CAA 0 issue "letsencrypt.org"
```

## QR Code Customization

The website includes a QR code for easy account creation. You can customize the logo in the center:

```nix
# Default: Delta Chat logo (matches upstream relay)
services.chatmail.www.qrLogo = pkgs.chatmail-www.defaultLogo;

# No logo (simple QR code)
services.chatmail.www.qrLogo = null;

# Custom logo
services.chatmail.www.qrLogo = ./my-logo.png;
```

### Logo Requirements

- **Format**: PNG with transparency (alpha channel)
- **Aspect ratio**: Square (1:1)
- **Recommended size**: 128x128px or larger (will be resized to ~64x64px)
- **Colors**: Black/white or grayscale works best for contrast
- **Transparency**: Use transparent background for best results

The logo is placed in the center of a 384x384px QR code. High error correction (30%) ensures the QR code remains scannable with the logo overlay.

## NixOS Configuration

### Minimal Configuration

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

### Production Configuration

```nix
{
  services.chatmail = {
    enable = true;
    openFirewall = true;
    domain = "chat.example.org";

    # ACME/Let's Encrypt
    acme.email = "admin@example.org";

    # Privacy policy contacts
    privacyMail = "privacy@example.org";
    privacyPostal = "Example GmbH, Street 1, 12345 City, Country";
    privacyPdo = "Data Protection Officer, Example GmbH";
    privacySupervisor = "State Data Protection Authority";

    # Storage limits
    maxMailboxSize = "500M";
    maxMessageSize = 31457280;  # 30MB
    deleteMailsAfter = "20";    # days
    inactiveUserDays = 90;

    # Rate limiting
    maxUserSendPerMinute = 60;
  };
}
```

## Deployment

1. **Configure DNS records** (see above)

2. **Wait for DNS propagation** (up to 48 hours, usually faster)

3. **Deploy NixOS configuration**:
   ```bash
   nixos-rebuild switch --flake .#server
   ```

4. **Verify services started**:
   ```bash
   systemctl status chatmail-*
   systemctl status postfix dovecot2 nginx opendkim
   ```

5. **Get DKIM record and add to DNS**:
   ```bash
   cat /var/lib/dkim/opendkim.txt
   ```

## Verification

### DNS Records

```bash
# MX record
dig +short MX chat.example.org

# SPF
dig +short TXT chat.example.org

# DKIM
dig +short TXT opendkim._domainkey.chat.example.org

# DMARC
dig +short TXT _dmarc.chat.example.org
```

### Service Connectivity

```bash
# HTTPS
curl -I https://chat.example.org/

# IMAPS
openssl s_client -connect chat.example.org:993

# SMTPS
openssl s_client -connect chat.example.org:465

# Submission
openssl s_client -connect chat.example.org:587 -starttls smtp
```

### Account Creation

```bash
# Test /new endpoint
curl -X POST https://chat.example.org/new
```

## Logs

```bash
# All chatmail services
journalctl -u 'chatmail-*' -f

# Postfix
journalctl -u postfix -f

# Dovecot
journalctl -u dovecot2 -f

# OpenDKIM
journalctl -u opendkim -f

# Nginx
journalctl -u nginx -f
```

## Paths

| Path | Description |
|------|-------------|
| `/etc/chatmail.ini` | Main configuration |
| `/var/lib/dkim/` | DKIM keys |
| `/var/lib/acme/` | TLS certificates |
| `/var/lib/chatmail/` | State and databases |
| `/var/vmail/` | User mailboxes |
| `/run/doveauth/` | Authentication socket |
| `/run/chatmail-metadata/` | Metadata socket |
| `/run/chatmail-lastlogin/` | Last login socket |

## Ports

| Port | Protocol | Service |
|------|----------|---------|
| 25 | TCP | SMTP (incoming mail) |
| 80 | TCP | HTTP (ACME challenges) |
| 143 | TCP | IMAP |
| 443 | TCP | HTTPS + ALPN (IMAPS/SMTPS) |
| 465 | TCP | SMTPS |
| 587 | TCP | Submission |
| 993 | TCP | IMAPS |
| 3478 | UDP | TURN/STUN |

## Troubleshooting

### Certificate Issues

```bash
# Check ACME status
systemctl status acme-chat.example.org.service

# Force renewal
systemctl start acme-chat.example.org.service
```

### Mail Delivery Issues

```bash
# Check postfix queue
postqueue -p

# Flush queue
postqueue -f

# Test SMTP
telnet chat.example.org 25
```

### DKIM Issues

```bash
# Check OpenDKIM status
systemctl status opendkim

# Test DKIM signing
opendkim-testkey -d chat.example.org -s opendkim -vvv
```

### Disable Account Creation

To temporarily stop new account creation:

```bash
touch /etc/chatmail-nocreate
```

Remove the file to re-enable.

## Security Notes

- All outgoing mail must be encrypted (enforced by filtermail)
- DKIM signatures are required for incoming mail
- Strict DMARC alignment (adkim=s, aspf=s)
- TLS required for all connections
- Accounts without login are deleted after configured days

## References

- [Delta Chat](https://delta.chat)
- [Chatmail Relay](https://github.com/chatmail/relay)
- [Chatmail Documentation](https://chatmail.at)
