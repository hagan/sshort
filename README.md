# sshort

**Short-lived SSH Certificates with YubiKey CA**

> SSH + Short = `sshort`

Create short-lived SSH certificates signed by a YubiKey-backed CA. No server required - your YubiKey *is* the CA.

```bash
sshort github +8h    # Get 8-hour certificate for GitHub
ssh -T git@github.com  # Just works
```

## Why?

- **SSH keys are permanent** - sshort certificates expire automatically
- **No server needed** - Your YubiKey is the CA (unlike step-ca, Vault, BLESS)
- **Hardware-backed security** - CA key never leaves YubiKey
- **Simple workflow** - One command to get a fresh certificate

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/USER/sshort/main/install.sh | bash

# Initialize config
sshort config init

# Edit to add your targets
sshort config edit

# Get certificates
sshort github +8h
```

## Requirements

- **YubiKey** with PIV support (YubiKey 5 series)
- **ykman** (YubiKey Manager CLI)
- **OpenSSH** 8.2+ (ssh-keygen, ssh-add)
- **bash** 4+ or **zsh** 5+

## Usage

```bash
# Basic usage
sshort                      # All targets, default validity (+8h)
sshort github               # Specific target
sshort +4h                  # All targets, 4 hours
sshort github +12h          # Specific target, 12 hours

# With options
sshort github +8h -S                    # Auto-detect source IP
sshort github +8h -O no-port-forwarding # Certificate options

# Management
sshort status               # Show certificate status
sshort clean                # Remove expired certificates
sshort remove github        # Remove specific certificate

# YubiKey
sshort yubikey list         # Show YubiKey configuration

# Configuration
sshort config show          # Show config
sshort config edit          # Edit config
sshort config init          # Create default config

# Diagnostics
sshort doctor               # Check setup
sshort help                 # Full help
```

## Configuration

Config file: `~/.config/sshort/config`

```ini
# Targets to manage
targets = github, myserver

# Default certificate validity
default_validity = +8h

# Where to store day keys
key_dir = ~/.ssh/keys

# GitHub target
[github]
principals = git

# Server with IP restriction
[myserver]
principals = admin
options = source-address=10.0.0.0/8

# YubiKey by serial number
[yubikey:12345678]
name = My YubiKey
ca_key = ~/.ssh/keys/id_ed25519_sk_CA
```

## How It Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  sshort     │────▶│  YubiKey    │────▶│  SSH Agent  │
│  (CLI)      │     │  (CA key)   │     │  (certs)    │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       ▼                   ▼                   ▼
  1. Generate         2. Sign with        3. Add cert
     day key             CA (touch!)         to agent
```

1. **Generate**: Creates ephemeral ED25519 "day key"
2. **Sign**: YubiKey CA signs it (requires physical touch)
3. **Add**: Certificate loaded into SSH agent with TTL
4. **Use**: SSH uses certificate for authentication
5. **Expire**: Certificate expires, run sshort again

## Initial Setup

### 1. Create CA Key on YubiKey

```bash
# Generate CA key in PIV slot 9d
ykman piv keys generate 9d - | \
  ykman piv certificates generate 9d - \
    --subject "SSH CA" --valid-days 3650

# Export CA public key
ssh-keygen -D /usr/lib/libykcs11.so -e > ~/.ssh/keys/id_ed25519_sk_CA.pub
```

### 2. Configure Servers

On each server, add to `/etc/ssh/sshd_config`:

```
TrustedUserCAKeys /etc/ssh/ca.pub
```

Copy your CA public key to `/etc/ssh/ca.pub` and restart sshd.

### 3. Configure sshort

```bash
sshort config init
sshort config edit
# Add your targets and YubiKey serial
```

## Shell Integration

Add to `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(sshort shell-init)"
```

This adds aliases:
- `sshcerts` - Show certificate status
- `sshort-4h`, `sshort-8h`, `sshort-12h`, `sshort-24h` - Quick validity presets

## Certificate Options

```bash
# Restrict to source IP
sshort myserver +8h -O source-address=10.0.0.0/8

# Auto-detect current IP
sshort myserver +8h --source-ip

# Disable features
sshort myserver +8h -O no-port-forwarding -O no-agent-forwarding

# Multiple options (in config)
[myserver]
principals = admin
options = source-address=10.0.0.0/8 no-x11-forwarding
```

## Comparison with Alternatives

| Tool | Server Required | Best For |
|------|-----------------|----------|
| **sshort** | No | Individual developers |
| step-ca | Yes | Organizations |
| Rustica | Yes | Enterprise (attestation) |
| HashiCorp Vault | Yes | Enterprise secrets |
| BLESS | Yes (Lambda) | AWS orgs (archived) |

## License

MIT
