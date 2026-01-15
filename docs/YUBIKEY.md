# YubiKey Setup for sshort

This guide covers setting up your YubiKey as a Certificate Authority (CA) for sshort.

## Prerequisites

- YubiKey 5 series (with PIV support)
- `ykman` (YubiKey Manager CLI)
- OpenSSH 8.2+

### Install ykman

```bash
# macOS
brew install ykman

# Ubuntu/Debian
sudo apt install yubikey-manager

# Arch
sudo pacman -S yubikey-manager

# Fedora
sudo dnf install yubikey-manager
```

## Understanding CA Key Options

sshort supports two types of CA keys:

| Type | Security | Extractable | Touch Required |
|------|----------|-------------|----------------|
| **PIV (slot 9d)** | Good | Yes (with credentials) | Per-signing |
| **FIDO2 resident** | Better | No | Per-signing |

### PIV Slot 9d (Recommended for Simplicity)

The PIV slot 9d (Key Management) is commonly used for SSH CAs. The key can be extracted if someone has the management key, but requires physical touch for each signing operation.

### FIDO2 Resident Key (Recommended for Security)

FIDO2 resident keys are truly hardware-bound and cannot be extracted. However, using them as SSH CAs is more complex.

## Option 1: PIV-based CA (Simpler)

### Step 1: Generate CA Key on YubiKey

```bash
# Create key directory
mkdir -p ~/.ssh/keys
chmod 700 ~/.ssh/keys

# Get YubiKey serial number
ykman info

# Generate EC P-384 key in slot 9d (Key Management)
ykman piv keys generate 9d --algorithm ECCP384 /tmp/ca_pubkey.pem

# Create self-signed certificate for the key
ykman piv certificates generate 9d /tmp/ca_pubkey.pem \
    --subject "CN=SSH CA" \
    --valid-days 3650

# Clean up temp file
rm /tmp/ca_pubkey.pem
```

### Step 2: Export CA Public Key

```bash
# Find PKCS#11 library path
# macOS: /usr/local/lib/libykcs11.dylib or /opt/homebrew/lib/libykcs11.dylib
# Linux: /usr/lib/libykcs11.so or /usr/lib/x86_64-linux-gnu/libykcs11.so

# Export public key in SSH format
ssh-keygen -D /usr/lib/libykcs11.so -e > ~/.ssh/keys/id_ed25519_sk_CA.pub

# Verify the key
cat ~/.ssh/keys/id_ed25519_sk_CA.pub
```

### Step 3: Test CA Signing

```bash
# Create a test key
ssh-keygen -t ed25519 -f /tmp/test_key -N ""

# Sign the test key (will prompt for PIN and touch)
ssh-keygen -s ~/.ssh/keys/id_ed25519_sk_CA.pub \
    -D /usr/lib/libykcs11.so \
    -I "test-cert" \
    -n "testuser" \
    -V "+1h" \
    /tmp/test_key.pub

# Verify certificate was created
ssh-keygen -L -f /tmp/test_key-cert.pub

# Clean up
rm /tmp/test_key /tmp/test_key.pub /tmp/test_key-cert.pub
```

## Option 2: FIDO2 Resident Key CA (More Secure)

### Step 1: Generate FIDO2 Resident Key

```bash
# Generate resident key on YubiKey
# This key CANNOT be extracted - it's truly hardware-bound
ssh-keygen -t ed25519-sk -O resident -O application=ssh:ca \
    -f ~/.ssh/keys/id_ed25519_sk_CA \
    -C "SSH CA (YubiKey)"

# This will prompt for YubiKey touch
```

### Step 2: Verify Key is Resident

```bash
# List resident keys on YubiKey
ssh-keygen -K

# Should show your CA key
```

### Limitations of FIDO2 CA

- Each signing operation requires touch (same as PIV)
- Key cannot be backed up (if YubiKey is lost, CA is gone)
- Consider having a backup YubiKey with a separate CA

## Configuring sshort

### Find Your YubiKey Serial

```bash
ykman info
# Look for "Serial number: XXXXXXXX"
```

### Add to sshort Config

```bash
sshort config edit
```

Add your YubiKey configuration:

```ini
# YubiKey configuration
[yubikey:12345678]
name = Primary YubiKey
ca_key = ~/.ssh/keys/id_ed25519_sk_CA
```

### Test sshort

```bash
# Check configuration
sshort doctor

# Should show:
# ✅ Connected: Primary YubiKey (12345678)
# ✅ CA Key: /home/user/.ssh/keys/id_ed25519_sk_CA
```

## Multiple YubiKeys

You can configure multiple YubiKeys with different or the same CA:

```ini
# Primary YubiKey
[yubikey:12345678]
name = Primary YubiKey (Nano)
ca_key = ~/.ssh/keys/id_ed25519_sk_CA

# Backup YubiKey (same CA)
[yubikey:87654321]
name = Backup YubiKey (USB-A)
ca_key = ~/.ssh/keys/id_ed25519_sk_CA

# Work YubiKey (different CA)
[yubikey:11223344]
name = Work YubiKey
ca_key = ~/.ssh/keys/id_ed25519_sk_CA_work
```

sshort automatically detects which YubiKey is inserted and uses the corresponding configuration.

## PIN Management

### Set PIV PIN (Recommended)

```bash
# Default PIN is 123456, default PUK is 12345678
# Change PIN (will prompt for current and new PIN)
ykman piv access change-pin

# Change PUK (recovery code)
ykman piv access change-puk
```

### PIN Policy

You can require PIN for PIV operations:

```bash
# Regenerate key with PIN requirement
ykman piv keys generate 9d --algorithm ECCP384 --pin-policy ALWAYS /tmp/ca.pem
```

## Touch Policy

By default, PIV slot 9d requires touch for each signing operation. This is the recommended behavior for a CA key.

To verify:

```bash
# Check slot configuration
ykman piv info
```

## Backup Considerations

### PIV CA Key

If using PIV, you can export/backup the key (before generating on YubiKey):

```bash
# Generate key locally first
openssl ecparam -name secp384r1 -genkey -out ca_private.pem

# Import to YubiKey
ykman piv keys import 9d ca_private.pem

# Store ca_private.pem securely (encrypted, offline)
```

**Warning**: This reduces security as the key exists outside the YubiKey.

### FIDO2 CA Key

FIDO2 resident keys **cannot be exported**. If your YubiKey is lost:

1. Generate new CA on new YubiKey
2. Update all servers with new CA public key
3. Re-sign all day keys

**Recommendation**: Set up a backup YubiKey with a second CA, and configure servers to trust both CAs.

## Troubleshooting

### "No YubiKey detected"

```bash
# Check YubiKey is recognized
ykman info

# Check USB connection
lsusb | grep Yubico  # Linux
system_profiler SPUSBDataType | grep -A5 YubiKey  # macOS
```

### "PIN required"

If you set a PIN policy, you'll be prompted for PIN on each operation. This is expected.

### "Touch timeout"

YubiKey touch times out after ~15 seconds. Watch for the blinking light and touch promptly.

### PKCS#11 Library Not Found

```bash
# Find the library
find /usr -name "libykcs11*" 2>/dev/null
find /opt -name "libykcs11*" 2>/dev/null

# Common locations:
# Linux: /usr/lib/libykcs11.so
# macOS Homebrew: /opt/homebrew/lib/libykcs11.dylib
# macOS Intel: /usr/local/lib/libykcs11.dylib
```

## Security Best Practices

1. **Enable PIN** - Don't use default PIN
2. **Physical security** - Keep YubiKey on your person or locked away
3. **Touch required** - Ensure touch policy is enabled (default for slot 9d)
4. **Backup strategy** - Have a plan for YubiKey loss
5. **Separate CAs** - Consider separate CAs for personal vs work

## References

- [Yubico PIV Guide](https://developers.yubico.com/PIV/)
- [SSH Certificate Documentation](https://man.openbsd.org/ssh-keygen#CERTIFICATES)
- [FIDO2 SSH Keys](https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html)
