# Testing in BusyBox Container

## Quick Start

```bash
./test-busybox.sh
```

This drops you into a BusyBox container with everything set up.

## Important Notes

### No `just` Command Available

BusyBox doesn't include `just` by default. Instead:

**Run scripts directly:**
```bash
cd /opt/keyboard_kowboys
./scripts/backup.sh -v network /tmp/test
```

**Justfile is available for reference:**
```bash
cat Justfile
```

To test `just` commands, you need a full Linux system with `just` installed.

## What's Set Up Automatically

When you run `./test-busybox.sh`, the container automatically:

1. Creates `/opt/keyboard_kowboys/` directory structure
2. Copies all scripts from `/test/scripts/` to `/opt/keyboard_kowboys/scripts/`
3. Copies `Justfile`, `ansible.cfg`, `hosts.ini` for reference
4. Makes scripts executable
5. Sets environment variables

## Environment Variables

These are automatically set:
```bash
KK_BASE_DIR=/opt/keyboard_kowboys
KK_CONFIG_DIR=/opt/keyboard_kowboys/configs
KK_LOG_DIR=/opt/keyboard_kowboys/logs
KK_BACKUP_DIR=/opt/keyboard_kowboys/backups
```

## Quick Tests

### Test 1: Syntax Check
```bash
cd /opt/keyboard_kowboys
sh -n scripts/backup.sh
```
No output = success!

### Test 2: View Help
```bash
./scripts/backup.sh --help
```

### Test 3: Dry Run
```bash
./scripts/backup.sh -d -v network /tmp/test
```

### Test 4: Real Backup
```bash
./scripts/backup.sh -v network /tmp/test
```

### Test 5: Verify
```bash
ls -la /tmp/test/network/latest/
cat logs/system-backup.log
```

### Test 6: Security Backup
```bash
./scripts/backup.sh -v security /tmp/test
ls -la /tmp/test/security/latest/system_info/
```

### Test 7: Save to Host
```bash
cp logs/system-backup.log /workspace/
cp -r /tmp/test/network/latest/system_info /workspace/
```

### Test 8: Persistence Detection
```bash
./scripts/check_persistence.sh --help
./scripts/check_persistence.sh --cron
./scripts/check_persistence.sh -v
cat logs/persistence-report-*.txt
```

### Test 9: Exit
```bash
exit
```

Files in `/workspace` will be at the temp directory shown at startup.

## Testing `just` Commands

To test actual `just` commands, you need to:

1. **Exit the BusyBox container**
2. **Test on your host system** (with `just` installed)
3. Or use a full Linux container

### On Host System

```bash
# Make sure just is installed
which just

# Run just commands
sudo just backup network
just diff ports
just status
```

## What BusyBox Tests

- ✅ POSIX shell syntax
- ✅ Script functionality
- ✅ Find command compatibility
- ✅ Basic tools (cp, mv, ls, etc.)
- ✅ Fallback handling for missing tools

## What BusyBox Doesn't Test

- ❌ `just` command runner
- ❌ Full systemd integration
- ❌ Advanced tools (systemd-analyze, aa-status, etc.)
- ❌ Ansible playbooks

For full testing, use the host system or a complete Linux container.

## Common Issues

### "just: command not found"
**Expected** - BusyBox doesn't have `just`. Run scripts directly:
```bash
./scripts/backup.sh -v network /tmp/test
```

### "systemctl: command not found"
**Expected** - BusyBox doesn't have systemd. Script handles this gracefully.

### "Permission denied"
**Run as root or check script permissions:**
```bash
chmod +x scripts/*.sh
```

### Can't write to filesystem
**Use writable areas:**
- `/tmp` - tmpfs (512MB)
- `/opt` - tmpfs (256MB)
- `/workspace` - persists to host

## Full Integration Testing

For complete testing including `just` commands:

```bash
# On your host machine (with just installed)
cd /path/to/just-linux

# Initialize
sudo just init

# Run backups
sudo just backup network
sudo just backup security
sudo just backup audit

# Compare
just diff ports
just diff processes

# Persistence Detection
sudo just check-persistence
sudo just check-persistence --cron --ssh
sudo just check-persistence -v

# Status
just status
```

## Testing Persistence Detection

### BusyBox Container Tests
```bash
# Test help
./scripts/check_persistence.sh --help

# Test specific checks (doesn't require root in container)
./scripts/check_persistence.sh --profiles
./scripts/check_persistence.sh --cron

# View results
cat /opt/keyboard_kowboys/logs/persistence-report-*.txt
```

### Full System Tests
```bash
# Create baseline backup first
sudo just backup all

# Run full persistence scan
sudo just check-persistence -v

# Test specific categories
sudo just check-persistence --cron
sudo just check-persistence --systemd
sudo just check-persistence --ssh --suid

# Review reports
ls -lh /opt/keyboard_kowboys/logs/persistence-report-*
tail -50 /opt/keyboard_kowboys/logs/persistence-report-*.txt
```

### Expected Behavior
- **Exit code 0**: No persistence mechanisms detected
- **Exit code 1**: Potential issues found (review report)
- **False positives**: System scripts using `eval` are normal
- **Reports saved**: Timestamped in logs directory

See `docs/persistence-detection.md` and `docs/99-Testing-Guide.md` for complete testing procedures.
