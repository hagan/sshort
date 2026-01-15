# Troubleshooting sshort

Common issues and solutions for sshort.

## Quick Diagnostics

```bash
# Run doctor first
sshort doctor

# Check certificate status
sshort status

# Verbose SSH connection
ssh -v server
```

## Installation Issues

### "sshort: command not found"

sshort isn't in your PATH.

```bash
# Check if installed
ls ~/.local/bin/sshort

# Add to PATH in ~/.bashrc or ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"

# Reload shell
source ~/.bashrc
```

### "ykman: NOT FOUND"

Install YubiKey Manager:

```bash
# macOS
brew install ykman

# Ubuntu/Debian
sudo apt install yubikey-manager

# Arch
sudo pacman -S yubikey-manager
```

## YubiKey Issues

### "No YubiKey detected"

```bash
# Check if YubiKey is recognized by system
ykman info

# Linux: Check USB
lsusb | grep -i yubi

# macOS: Check USB
system_profiler SPUSBDataType | grep -A5 -i yubi

# If not detected, try:
# 1. Different USB port
# 2. Different cable (if USB-C)
# 3. Check if pcscd is running (Linux)
sudo systemctl status pcscd
sudo systemctl start pcscd
```

### "Touch timeout"

YubiKey blinks for ~15 seconds waiting for touch.

**Solution**: Watch for the blinking light and touch immediately.

**Tip**: If running in a terminal you're not watching, set a longer timeout or use a notification.

### "PIN required" / "Wrong PIN"

```bash
# Check PIN retry counter
ykman piv info

# If locked out, reset with PUK
ykman piv access unblock-pin

# If PUK also locked, factory reset PIV (destroys all keys!)
ykman piv reset
```

### "CA key not found"

```bash
# Check configured CA path
sshort config show | grep ca_key

# Verify file exists
ls -la ~/.ssh/keys/id_ed25519_sk_CA*

# If missing, re-export from YubiKey
ssh-keygen -D /usr/lib/libykcs11.so -e > ~/.ssh/keys/id_ed25519_sk_CA.pub
```

## Certificate Issues

### "Certificate not accepted"

SSH connection fails with certificate.

**Debug:**
```bash
# Check certificate details
ssh-keygen -L -f ~/.ssh/keys/id_ed25519_day_myserver-cert.pub

# Verbose SSH
ssh -v myserver 2>&1 | grep -i cert
```

**Common causes:**

1. **Certificate expired**
   ```bash
   sshort status myserver
   # If expired, regenerate
   sshort myserver +8h
   ```

2. **Wrong principal**
   ```bash
   # Check certificate principal
   ssh-keygen -L -f ~/.ssh/keys/id_ed25519_day_myserver-cert.pub | grep Principals

   # Check server's allowed principals
   # On server: /etc/ssh/auth_principals/<username>
   ```

3. **Server doesn't trust CA**
   ```bash
   # On server, verify CA is configured
   grep TrustedUserCAKeys /etc/ssh/sshd_config

   # Verify CA file exists and matches
   cat /etc/ssh/ca.pub
   ```

4. **source-address restriction**
   ```bash
   # Check if IP restricted
   ssh-keygen -L -f ~/.ssh/keys/id_ed25519_day_myserver-cert.pub | grep source-address

   # Your IP may have changed
   curl ifconfig.me
   ```

### "Permission denied (publickey)"

```bash
# 1. Check certificate is in agent
ssh-add -l

# 2. If not, add it
sshort myserver +8h

# 3. Check agent is running
echo $SSH_AUTH_SOCK

# 4. If using forwarded agent, it may have timed out
# Regenerate certificate on local machine
```

### Certificate Shows Valid But SSH Fails

Check the certificate's critical options:

```bash
ssh-keygen -L -f ~/.ssh/keys/id_ed25519_day_myserver-cert.pub

# Look for:
# - source-address (IP restriction)
# - force-command (command restriction)
# - Validity period
```

## SSH Agent Issues

### "Could not add key to agent"

```bash
# Check agent is running
echo $SSH_AUTH_SOCK
ssh-add -l

# If not running, start it
eval "$(ssh-agent -s)"

# If using Secretive (macOS)
# Secretive doesn't support adding external keys
# sshort will show a message about this
```

### Certificate Not Used

SSH might prefer other keys over certificates.

```bash
# List agent keys
ssh-add -l

# Force certificate use
ssh -i ~/.ssh/keys/id_ed25519_day_myserver myserver

# Or add to ~/.ssh/config
Host myserver
    IdentityFile ~/.ssh/keys/id_ed25519_day_myserver
    IdentitiesOnly yes
```

### Agent Forwarding Not Working

```bash
# Check certificate allows forwarding
ssh-keygen -L -f ~/.ssh/keys/id_ed25519_day_myserver-cert.pub | grep -i forward

# If "no-agent-forwarding" is set, certificate blocks it
# Regenerate without that option
sshort myserver +8h  # without -O no-agent-forwarding
```

## Configuration Issues

### "No targets configured"

```bash
# Check config exists
cat ~/.config/sshort/config

# If missing, create default
sshort config init

# Edit to add targets
sshort config edit
```

### Config Not Being Read

```bash
# Check config file location
echo $SSHORT_CONFIG

# Default location
ls -la ~/.config/sshort/config

# Verify syntax (no tabs, proper sections)
sshort config show
```

### Wrong YubiKey CA Used

If you have multiple YubiKeys configured:

```bash
# Check which is detected
sshort yubikey list

# Verify serial number matches config
ykman info | grep Serial
```

## Server-Side Issues

### Server Rejects All Certificates

On the server:

```bash
# Check sshd config
sudo grep -i trusted /etc/ssh/sshd_config

# Verify CA file
sudo cat /etc/ssh/ca.pub

# Check sshd logs
sudo journalctl -u sshd -f
# Or
sudo tail -f /var/log/auth.log
```

### AuthorizedPrincipals Issues

If using principal mapping:

```bash
# Check principal file exists
ls -la /etc/ssh/auth_principals/

# Check your username's principals
cat /etc/ssh/auth_principals/$(whoami)

# Verify certificate principal matches
ssh-keygen -L -f ~/.ssh/keys/id_ed25519_day_myserver-cert.pub | grep Principals
```

## Performance Issues

### Slow Certificate Generation

Certificate signing is limited by YubiKey touch speed (~1 per second).

For multiple targets:
```bash
# Generate all at once (still requires touch per target)
sshort +8h
```

### Agent Bloat

Too many keys in agent:

```bash
# List all keys
ssh-add -l

# Remove all
ssh-add -D

# Add only what you need
sshort myserver +8h
```

## Recovery Procedures

### Lost YubiKey

1. **Revoke access**: Remove the lost YubiKey's CA from all servers
2. **Generate new CA**: On backup or new YubiKey
3. **Update servers**: Add new CA public key
4. **Update sshort config**: Remove old YubiKey entry

### Expired Certificate During Session

If certificate expires while working:

```bash
# Simply regenerate
sshort myserver +8h

# Existing SSH sessions may continue working
# New connections need the new certificate
```

### Corrupted Day Key

```bash
# Remove day keys for target
rm ~/.ssh/keys/id_ed25519_day_myserver*

# Regenerate
sshort myserver +8h
```

## Getting Help

### Collect Debug Info

```bash
# Full diagnostic
sshort doctor
sshort status
ssh-add -l
ykman info

# Save to file
{
  echo "=== sshort doctor ==="
  sshort doctor
  echo "=== sshort status ==="
  sshort status
  echo "=== ssh-add -l ==="
  ssh-add -l
  echo "=== ykman info ==="
  ykman info
} > sshort-debug.txt
```

### Report Issues

GitHub: https://github.com/hagan/sshort/issues

Include:
- sshort version (`sshort version`)
- OS and version
- Debug output (remove sensitive info)
- Steps to reproduce
