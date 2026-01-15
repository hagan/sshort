# Multi-YubiKey / Multi-CA Setup

sshort supports multiple YubiKeys, each with their own CA. This is useful for:

- **Redundancy** - Backup keys in case one is lost
- **Separation** - Different CAs for personal vs work
- **Flexibility** - Use whichever YubiKey is handy

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                     Multi-CA Architecture                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  YubiKey A (Nano)          YubiKey B (USB-C)                    │
│  Serial: 12345678          Serial: 87654321                     │
│  CA: ca_key_a              CA: ca_key_b                         │
│       │                          │                               │
│       ▼                          ▼                               │
│  Signs certs with A         Signs certs with B                  │
│                                                                  │
│                    Server                                        │
│              ┌─────────────┐                                     │
│              │ TrustedCA:  │                                     │
│              │  - ca_key_a │  ◄── Trusts BOTH CAs               │
│              │  - ca_key_b │                                     │
│              └─────────────┘                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Setup

### Step 1: Create CA on Each YubiKey

For each YubiKey, create a CA key:

```bash
# Insert YubiKey A
ykman info  # Note serial: 12345678

# Generate CA
ykman piv keys generate 9d --algorithm ECCP384 /tmp/ca.pem
ykman piv certificates generate 9d /tmp/ca.pem \
    --subject "CN=SSH CA A" --valid-days 3650
rm /tmp/ca.pem

# Export public key
ssh-keygen -D /usr/lib/libykcs11.so -e > ~/.ssh/keys/ca_a.pub

# Repeat for YubiKey B, C, D...
# Insert YubiKey B
ykman info  # Note serial: 87654321

ykman piv keys generate 9d --algorithm ECCP384 /tmp/ca.pem
ykman piv certificates generate 9d /tmp/ca.pem \
    --subject "CN=SSH CA B" --valid-days 3650
rm /tmp/ca.pem

ssh-keygen -D /usr/lib/libykcs11.so -e > ~/.ssh/keys/ca_b.pub
```

### Step 2: Configure sshort

```ini
# ~/.config/sshort/config

targets = github, myserver

default_validity = +8h

[github]
principals = git

[myserver]
principals = admin

# YubiKey A - Nano (always in laptop)
[yubikey:12345678]
name = YubiKey Nano (Laptop)
ca_key = ~/.ssh/keys/ca_a

# YubiKey B - USB-C (keychain)
[yubikey:87654321]
name = YubiKey USB-C (Keychain)
ca_key = ~/.ssh/keys/ca_b

# YubiKey C - Backup (safe)
[yubikey:11111111]
name = YubiKey Backup (Safe)
ca_key = ~/.ssh/keys/ca_c

# YubiKey D - Work
[yubikey:22222222]
name = YubiKey Work
ca_key = ~/.ssh/keys/ca_d
```

### Step 3: Configure Servers to Trust All CAs

On each server, concatenate all CA public keys:

```bash
# On your workstation - create combined CA file
cat ~/.ssh/keys/ca_a.pub \
    ~/.ssh/keys/ca_b.pub \
    ~/.ssh/keys/ca_c.pub \
    ~/.ssh/keys/ca_d.pub > /tmp/all_cas.pub

# Copy to server
scp /tmp/all_cas.pub server:/tmp/

# On server - install combined CA
sudo mv /tmp/all_cas.pub /etc/ssh/trusted_cas.pub
sudo chmod 644 /etc/ssh/trusted_cas.pub
```

Update `/etc/ssh/sshd_config`:

```
TrustedUserCAKeys /etc/ssh/trusted_cas.pub
```

Restart SSH:
```bash
sudo systemctl restart sshd
```

## Usage

sshort automatically detects which YubiKey is inserted:

```bash
# Insert YubiKey A
sshort doctor
# ✅ Connected: YubiKey Nano (Laptop) (12345678)
# ✅ CA Key: ~/.ssh/keys/ca_a

sshort myserver +8h
# Signs with CA A

# Insert YubiKey B instead
sshort doctor
# ✅ Connected: YubiKey USB-C (Keychain) (87654321)
# ✅ CA Key: ~/.ssh/keys/ca_b

sshort myserver +8h
# Signs with CA B
```

Both certificates are accepted by the server because it trusts both CAs.

## Use Cases

### 1. Backup Keys

Keep a backup YubiKey in a safe with the same or different CA:

```ini
[yubikey:12345678]
name = Primary
ca_key = ~/.ssh/keys/ca_primary

[yubikey:87654321]
name = Backup (in safe)
ca_key = ~/.ssh/keys/ca_backup
```

If primary is lost:
1. Use backup YubiKey
2. Generate new CA on replacement YubiKey
3. Update servers with new CA
4. Remove old CA from servers

### 2. Work/Personal Separation

Different CAs for different trust domains:

```ini
[yubikey:12345678]
name = Personal
ca_key = ~/.ssh/keys/ca_personal

[yubikey:87654321]
name = Work
ca_key = ~/.ssh/keys/ca_work
```

Personal servers trust only `ca_personal`.
Work servers trust only `ca_work`.

### 3. Form Factor Convenience

Same CA on different form factors:

```bash
# Export CA from primary YubiKey
# Then import to backup (loses hardware-binding benefit)
# OR use same CA key file for both (if using file-based CA)
```

**Warning**: Sharing CA keys between YubiKeys reduces security.

### 4. Gradual Migration

When rotating CAs:

1. Generate new CA on new YubiKey
2. Add new CA to all servers (alongside old)
3. Start using new YubiKey
4. After transition period, remove old CA from servers

## Checking Which YubiKey Is Active

```bash
# Show current YubiKey
sshort yubikey list

# Or check doctor output
sshort doctor
```

## Troubleshooting

### Wrong CA Being Used

If certificates aren't accepted:

```bash
# Check which YubiKey is detected
sshort yubikey list

# Verify the CA key exists
ls -la $(sshort config show | grep ca_key | head -1 | awk -F= '{print $2}')

# Check server trusts this CA
ssh -v server 2>&1 | grep -i cert
```

### Adding New YubiKey

1. Generate CA on new YubiKey
2. Add to sshort config
3. Add CA public key to all servers
4. Test: `sshort myserver +1h && ssh myserver`

### Removing Old YubiKey

1. Remove from sshort config
2. Remove CA from all servers
3. Securely destroy the YubiKey (if compromised)
