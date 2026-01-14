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
curl -fsSL https://raw.githubusercontent.com/hagan/sshort/main/install.sh | bash

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

## Security Considerations

### ⚠️ Important: Understand the Trade-offs

sshort is designed for **personal use** by individual developers. It is **not** a replacement for enterprise certificate management systems like step-ca or HashiCorp Vault.

### Threat Model

**sshort is better than permanent SSH keys** because:
- Certificates expire automatically (limited exposure window)
- No key distribution problem (servers trust CA, not individual keys)

**But sshort has risks you must understand:**

### 1. CA Compromise = Total Compromise

If someone obtains your CA private key, they can sign certificates for **any principal** your servers trust. This is catastrophic.

**Mitigations:**
- Store CA key on YubiKey (requires physical touch to sign)
- Use PIN protection on YubiKey
- Keep YubiKey physically secure

**Warning about PIV vs FIDO2:**
```
PIV slot (ykman piv)     → Key CAN be extracted with management key
FIDO2 resident key       → Key CANNOT be extracted (truly hardware-bound)
```

If using PIV slot 9d, your CA key is **extractable** by someone with physical access and credentials. For higher security, consider using a FIDO2 resident key as your CA.

### 2. Day Keys are Passwordless

Day keys are generated without passwords for convenience. If someone copies both:
- `~/.ssh/keys/id_ed25519_day_*` (private key)
- `~/.ssh/keys/id_ed25519_day_*-cert.pub` (certificate)

They have valid credentials until the certificate expires.

**Mitigations:**
- Keep validity short (4-8 hours recommended)
- Protect key directory: `chmod 700 ~/.ssh/keys`
- Run `sshort clean` regularly

### 3. No Certificate Revocation

SSH certificates have **no revocation mechanism**. If a certificate is compromised:
- Wait for expiry, OR
- Manually add key ID to revocation list on every server

Short validity periods (4-8h) limit exposure but don't eliminate it.

### 4. Principal Scope

Be careful with principal naming. If your CA signs certificates for principal "git" (GitHub) AND you have a server accepting "git" for admin access, you've created unintended cross-access.

**Best practice:** Use unique, descriptive principals per trust boundary.

### 5. Agent Forwarding

If you forward your SSH agent (`ssh -A`), anyone with root on the remote server can use your certificates.

**Mitigations:**
- Use `no-agent-forwarding` certificate option
- Avoid agent forwarding when possible

### Recommendations

| Setting | Recommended | Why |
|---------|-------------|-----|
| Validity | 4-8 hours | Limits exposure window |
| CA key type | FIDO2 resident | Truly hardware-bound |
| Certificate options | `source-address`, `no-agent-forwarding` | Restricts usage |
| Key directory | `chmod 700` | Prevents local theft |

### When NOT to Use sshort

- **Production infrastructure** - Use step-ca or Vault with proper audit trails
- **Multi-user environments** - No centralized policy enforcement
- **High-security systems** - Consider pure FIDO2 keys (no certificates)
- **Systems requiring revocation** - SSH certs can't be revoked instantly

### Security Comparison

| Approach | CA Compromise | Key Theft | Revocation |
|----------|---------------|-----------|------------|
| Permanent SSH keys | N/A | Permanent access | Manual removal |
| **sshort** | Total compromise | Time-limited | Wait for expiry |
| FIDO2 keys (no certs) | N/A | Impossible | Manual removal |
| step-ca | Server compromise | Time-limited | Server-side |

## Comparison with Alternatives

| Tool | Server Required | Best For |
|------|-----------------|----------|
| **sshort** | No | Individual developers, homelabs |
| step-ca | Yes | Organizations with policy needs |
| Rustica | Yes | Enterprise (attestation) |
| HashiCorp Vault | Yes | Enterprise secrets management |
| BLESS | Yes (Lambda) | AWS organizations (archived) |
| Pure FIDO2 keys | No | Maximum security, less convenience |

## License

MIT
