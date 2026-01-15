# sshort Setup Guide

Complete guide to setting up sshort for SSH certificate management.

## Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        Setup Process                              │
├──────────────────────────────────────────────────────────────────┤
│  1. Install sshort                                                │
│  2. Set up YubiKey CA                                            │
│  3. Configure sshort                                              │
│  4. Configure servers to trust CA                                 │
│  5. Test connection                                               │
└──────────────────────────────────────────────────────────────────┘
```

## Step 1: Install sshort

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/hagan/sshort/main/install.sh | bash
```

### Manual Install

```bash
# Clone repository
git clone https://github.com/hagan/sshort.git
cd sshort

# Install
./install.sh

# Or manually copy
cp sshort ~/.local/bin/
chmod +x ~/.local/bin/sshort
```

### Verify Installation

```bash
sshort version
sshort doctor
```

## Step 2: Set Up YubiKey CA

See [YUBIKEY.md](YUBIKEY.md) for detailed YubiKey setup instructions.

### Quick PIV Setup

```bash
# Create key directory
mkdir -p ~/.ssh/keys
chmod 700 ~/.ssh/keys

# Generate CA key on YubiKey
ykman piv keys generate 9d --algorithm ECCP384 /tmp/ca.pem
ykman piv certificates generate 9d /tmp/ca.pem \
    --subject "CN=SSH CA" --valid-days 3650
rm /tmp/ca.pem

# Export public key
ssh-keygen -D /usr/lib/libykcs11.so -e > ~/.ssh/keys/id_ed25519_sk_CA.pub
```

## Step 3: Configure sshort

### Initialize Config

```bash
sshort config init
```

### Edit Config

```bash
sshort config edit
```

Example configuration:

```ini
# ~/.config/sshort/config

# Targets to manage
targets = github, myserver, workbox

# Default certificate validity
default_validity = +8h

# Where to store day keys
key_dir = ~/.ssh/keys

# Default CA key
ca_key = ~/.ssh/keys/id_ed25519_sk_CA

# ─────────────────────────────────────
# Target Configurations
# ─────────────────────────────────────

[github]
principals = git

[myserver]
principals = admin
options = source-address=10.0.0.0/8

[workbox]
principals = hagan
options = no-agent-forwarding

# ─────────────────────────────────────
# YubiKey Configuration
# ─────────────────────────────────────

[yubikey:12345678]
name = My YubiKey 5
ca_key = ~/.ssh/keys/id_ed25519_sk_CA
```

### Verify Config

```bash
sshort config show
sshort doctor
```

## Step 4: Configure Servers

### For Each Server

1. Copy CA public key to server:

```bash
# From your workstation
scp ~/.ssh/keys/id_ed25519_sk_CA.pub server:/tmp/
```

2. On the server, add CA to SSH config:

```bash
# As root on server
sudo mv /tmp/id_ed25519_sk_CA.pub /etc/ssh/ca.pub
sudo chmod 644 /etc/ssh/ca.pub
```

3. Edit `/etc/ssh/sshd_config`:

```
# Trust our CA for user authentication
TrustedUserCAKeys /etc/ssh/ca.pub

# Optional: Restrict which principals can log in as which users
# AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
```

4. Restart SSH:

```bash
sudo systemctl restart sshd
```

### Principal Mapping (Optional)

For fine-grained control, create principal files:

```bash
# /etc/ssh/auth_principals/root
admin
emergency

# /etc/ssh/auth_principals/deploy
deploy
ci

# /etc/ssh/auth_principals/hagan
hagan
admin
```

Then in sshd_config:
```
AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
```

### GitHub Setup

GitHub automatically trusts certificates signed by your CA if you upload the CA public key:

1. Go to GitHub → Settings → SSH and GPG keys
2. Click "New SSH key"
3. Paste contents of `~/.ssh/keys/id_ed25519_sk_CA.pub`
4. Use principal `git` when signing certificates

**Note**: GitHub doesn't actually support SSH CAs for regular users. Use regular SSH keys or FIDO2 keys for GitHub. The `github` target in sshort is useful if you're using GitHub Enterprise with CA support.

## Step 5: Test Connection

### Generate Certificate

```bash
# Generate certificate for a target
sshort myserver +8h

# Output:
# 🚀 Complete day key setup for: myserver (validity: +8h)
# 🔑 Generating new day key...
# 🔐 Signing with YubiKey CA...
# 👆 Touch YubiKey when it blinks...
# ✅ Certificate created
# ✅ Day key added to agent
```

### Verify Certificate

```bash
sshort status myserver

# Output:
# 🎯 Target: myserver
#    Valid: from 2025-01-14T10:00:00 to 2025-01-14T18:00:00
#    Status: ✅ Valid
#    Principals: admin
```

### Test SSH Connection

```bash
ssh myserver

# Should connect without password prompt
```

### Debug Connection Issues

```bash
# Verbose SSH output
ssh -v myserver

# Check certificate details
ssh-keygen -L -f ~/.ssh/keys/id_ed25519_day_myserver-cert.pub
```

## Shell Integration

### Bash

Add to `~/.bashrc`:

```bash
# sshort integration
eval "$(sshort shell-init)"

# Optional: Load completions
source /path/to/sshort/completions/sshort.bash
```

### Zsh

Add to `~/.zshrc`:

```bash
# sshort integration
eval "$(sshort shell-init)"

# Optional: Add completions to fpath
fpath=(/path/to/sshort/completions $fpath)
autoload -Uz compinit && compinit
```

### dcfg-tsb Integration

If using dcfg-tsb, sshort is automatically integrated via `shell/posix/modules/sshort.sh`.

## Daily Workflow

### Morning Routine

```bash
# Get fresh certificates for the day
sshort +8h

# Or use preset aliases
sshort-8h
```

### Check Status

```bash
# See all certificate status
sshort status

# Or use alias
sshcerts
```

### End of Day

```bash
# Clean up expired certificates
sshort clean
```

## Advanced Configuration

### Source IP Restriction

Restrict certificates to your current IP:

```bash
# Auto-detect IP
sshort myserver +8h --source-ip

# Manual IP/CIDR
sshort myserver +8h -O source-address=192.168.1.100/32
```

### Disable Features

```bash
# No port forwarding
sshort myserver +8h -O no-port-forwarding

# No agent forwarding
sshort myserver +8h -O no-agent-forwarding

# Multiple restrictions
sshort myserver +8h -O no-port-forwarding -O no-x11-forwarding
```

### Per-Target Defaults

Set options in config so they're always applied:

```ini
[production-server]
principals = deploy
options = source-address=10.0.0.0/8 no-port-forwarding no-agent-forwarding
```

## Next Steps

- Read [YUBIKEY.md](YUBIKEY.md) for detailed YubiKey configuration
- Read [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- Review security considerations in the main README
