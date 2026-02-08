# DockArr Stack Refactor: WSL2-Native Docker + DSC v3

## Summary

Remove Docker Desktop dependency by running Docker Engine natively in WSL2 Ubuntu, with Microsoft DSC v3 handling idempotent setup and validation.

## Architecture Change

```
BEFORE (Docker Desktop):
  PowerShell → Docker Desktop → WSL2 backend → Containers

AFTER (Native WSL):
  PowerShell → wsl -d Ubuntu -- docker → Native Docker Engine → Containers
```

## Files to Create

| File | Purpose |
|------|---------|
| `dockarr-setup.dsc.yaml` | DSC v3 config: directories, rclone.conf copy, validation |
| `wsl-setup.sh` | Shell script for Ubuntu: Docker, FUSE, systemd config |

## Files to Modify

| File | Changes |
|------|---------|
| `Setup-DockarrStack.ps1` | Complete rewrite: DSC v3 install → DSC apply → WSL Ubuntu install → wsl-setup.sh → validate |
| `Start-DockarrStack.ps1` | Replace `docker` with `wsl -d Ubuntu -- docker`, replace `wsl --shutdown` with `fusermount -u` |
| `Stop-DockarrStack.ps1` | Replace `docker` with `wsl -d Ubuntu -- docker`, add `-TerminateWSL` flag |
| `docker-compose.yml` | Convert all `C:/` paths to `/mnt/c/` paths in-place |
| `CLAUDE.md` | Document new architecture and command patterns |

---

## Implementation Steps

### Step 1: Create `dockarr-setup.dsc.yaml`

DSC v3 configuration for Windows-side setup:

```yaml
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2024/04/config/document.json
resources:
  # Directory structure (C:\docker-data\*)
  - name: CreateDirectories
    type: Microsoft.Windows/WindowsPowerShell
    properties:
      resources:
        - name: DockerDataRoot
          type: PSDesiredStateConfiguration/File
          properties:
            DestinationPath: 'C:\docker-data'
            Type: Directory
            Ensure: Present
        # ... subdirectories for each service

  # rclone.conf copy
  - name: RcloneConfig
    type: Microsoft.Windows/WindowsPowerShell
    properties:
      resources:
        - name: CopyRcloneConf
          type: PSDesiredStateConfiguration/Script
          properties:
            TestScript: Test-Path 'C:\docker-data\rclone.conf'
            SetScript: Copy-Item '.\rclone.conf' 'C:\docker-data\rclone.conf'
```

### Step 2: Create `wsl-setup.sh`

Shell script to run inside Ubuntu WSL:

```bash
#!/bin/bash
# wsl-setup.sh - Configure Ubuntu WSL for Docker and FUSE

set -e

echo "=== Ubuntu WSL Setup for DockArr Stack ==="

# Step 1: Update packages
sudo apt-get update

# Step 2: Install Docker prerequisites
sudo apt-get install -y ca-certificates curl gnupg

# Step 3: Add Docker GPG key and repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Step 4: Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Step 5: Install FUSE
sudo apt-get install -y fuse3

# Step 6: Configure FUSE for user_allow_other
if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "user_allow_other" | sudo tee -a /etc/fuse.conf
fi

# Step 7: Add current user to docker group
sudo usermod -aG docker $USER

# Step 8: Enable systemd in WSL
cat << 'EOF' | sudo tee /etc/wsl.conf
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true

[automount]
enabled=true
root=/mnt/
options="metadata,umask=22,fmask=11"
EOF

# Step 9: Start Docker (if systemd already running)
sudo systemctl enable docker
sudo systemctl start docker || true

echo ""
echo "=== Setup Complete ==="
echo "NOTE: WSL restart required for systemd. Run: wsl --terminate Ubuntu"
```

### Step 3: Modify `docker-compose.yml` in-place

Convert all Windows paths to WSL paths:

- `C:/docker-data/` → `/mnt/c/docker-data/`
- All 40+ volume mounts get this conversion
- Use sed/PowerShell regex replacement

### Step 4: Rewrite `Setup-DockarrStack.ps1`

```powershell
# Step 1: Install DSC v3
$dscPath = "$env:ProgramFiles\DSC"
if (-not (Test-Path "$dscPath\dsc.exe")) {
    $zipUrl = (Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/DSC/releases/latest').assets |
        Where-Object { $_.name -match 'x86_64-pc-windows-msvc\.zip$' } |
        Select-Object -ExpandProperty browser_download_url
    # Download, extract, add to PATH...
}

# Step 2: Apply DSC configuration
dsc config set --file dockarr-setup.dsc.yaml

# Step 3: Install Ubuntu WSL (if not present)
if ((wsl --list --quiet) -notmatch "Ubuntu") {
    wsl --install -d Ubuntu
}

# Step 4: Run wsl-setup.sh in Ubuntu
wsl -d Ubuntu -- bash /mnt/c/Users/Admin/DockArr-Stack/wsl-setup.sh

# Step 5: Restart WSL for systemd
wsl --terminate Ubuntu
Start-Sleep -Seconds 2

# Step 6: Validate Docker
wsl -d Ubuntu -- docker --version

# Step 7: Pull images (optional)
wsl -d Ubuntu -- docker compose -f /mnt/c/Users/Admin/DockArr-Stack/docker-compose.yml pull
```

### Step 5: Modify `Start-DockarrStack.ps1`

Key changes:
```powershell
# OLD: docker compose down
# NEW:
wsl -d Ubuntu -- docker compose -f /mnt/c/Users/Admin/DockArr-Stack/docker-compose.yml down

# OLD: wsl --shutdown
# NEW: (more targeted)
wsl -d Ubuntu -- fusermount -u /mnt/c/docker-data/gdrive 2>/dev/null

# OLD: docker compose up -d
# NEW:
wsl -d Ubuntu -- docker compose -f /mnt/c/Users/Admin/DockArr-Stack/docker-compose.yml up -d

# OLD: docker inspect
# NEW:
wsl -d Ubuntu -- docker inspect --format='{{.State.Health.Status}}' rclone
```

Also add Docker daemon startup check:
```powershell
$dockerInfo = wsl -d Ubuntu -- docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    wsl -d Ubuntu -- sudo systemctl start docker
}
```

### Step 6: Modify `Stop-DockarrStack.ps1`

Key changes:
```powershell
# Replace all docker commands with wsl -d Ubuntu -- docker

# Change -ShutdownWSL to -TerminateWSL (more accurate naming)
if ($TerminateWSL) {
    wsl --terminate Ubuntu
}

# Add explicit FUSE unmount
wsl -d Ubuntu -- fusermount -u /mnt/c/docker-data/gdrive 2>/dev/null
```

### Step 7: Update `CLAUDE.md`

Document:
- New architecture (no Docker Desktop)
- Command patterns (`wsl -d Alpine -- docker`)
- DSC v3 usage
- Troubleshooting for WSL-specific issues

---

## Key Technical Details

### FUSE in Ubuntu WSL

The rclone container needs:
- `/dev/fuse` device access
- `--allow-other` flag requires `/etc/fuse.conf` with `user_allow_other`
- Both handled by `wsl-setup.sh`

### Docker in Ubuntu WSL

Ubuntu uses systemd (enabled via wsl.conf):
- `sudo systemctl start docker`
- `sudo systemctl enable docker` for auto-start
- WSL config: `[boot] systemd=true`

### Path Conversion

Simple regex replacement in docker-compose.yml:
```powershell
# Convert C:/path to /mnt/c/path
(Get-Content docker-compose.yml) -replace 'C:/', '/mnt/c/' | Set-Content docker-compose.yml
```

Example: `C:/docker-data/sonarr` → `/mnt/c/docker-data/sonarr`

---

## Validation Checklist

After implementation, verify:

1. [ ] `dsc config test --file dockarr-setup.dsc.yaml` passes
2. [ ] `wsl -d Ubuntu -- docker info` succeeds
3. [ ] `wsl -d Ubuntu -- ls /dev/fuse` exists
4. [ ] `wsl -d Ubuntu -- grep user_allow_other /etc/fuse.conf` returns match
5. [ ] `.\Start-DockarrStack.ps1` brings up all 24 containers
6. [ ] rclone container reaches healthy state
7. [ ] Services accessible at expected ports (8989, 7878, etc.)
