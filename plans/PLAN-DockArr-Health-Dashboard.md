# Health Dashboard Implementation Plan

## Overview
Implement a monitoring dashboard for the DockArr stack using a simple, maintainable approach.

## Requirements Gathered
- Monitor all Docker containers health
- Monitor dual ISP WAN links (router handles failover)
- Track last successful run for each component
- Monitor local resources (CPU, RAM, disk I/O)
- Monitor disk space
- Monitor SMART status for Storage Spaces RAID

## System Context
- **Storage**: Windows Storage Spaces "RaidPool" (Parity, 4x16TB Seagate, ~42.5TB usable)
- **Network**: Dual ISP with router-level failover (server sees single gateway 10.0.0.1)
- **Preference**: Dashboard only (no alerts), simple stack

---

## Implementation Plan

### Services to Add

#### 1. Uptime Kuma (Primary Dashboard)
- **Purpose**: Service health monitoring, uptime tracking, response times
- **Port**: 3001
- **Config storage**: `C:/docker-data/uptime-kuma`

**Will monitor:**
- All DockArr services (HTTP checks):
  - Sonarr (http://sonarr:8989)
  - Radarr (http://radarr:7878)
  - Prowlarr (http://prowlarr:9696)
  - Bazarr (http://bazarr:6767)
  - Overseerr (http://overseerr:5055)
  - Tautulli (http://tautulli:8181)
  - RDTClient (http://rdtclient:6500)
  - Tdarr (http://tdarr:8265)
  - FlareSolverr (http://flaresolverr:8191)
  - Recyclarr (container status via Docker socket)
- WAN connectivity (ping/HTTP checks to external targets):
  - 8.8.8.8 (Google DNS)
  - 1.1.1.1 (Cloudflare DNS)
  - Real-Debrid API endpoint
- Docker host status

#### 2. Glances (Resource Monitoring)
- **Purpose**: Real-time CPU, RAM, disk I/O, network stats
- **Port**: 61208 (web UI)
- **Mode**: Web server mode with no password for local access

**Will show:**
- CPU usage
- RAM usage
- Container stats via Docker socket
- Network throughput (container level)

**Note**: On Docker Desktop for Windows, Glances has limited host visibility. It will show container metrics well but may not show Windows host CPU/RAM accurately. The Windows Health endpoint will supplement this.

### 3. Windows Health Endpoint (Native PowerShell)
- **Purpose**: Expose Windows-specific health data via HTTP
- **Port**: 9100
- **Implementation**: PowerShell script running as Windows Task (not in Docker - needs host access)

**Will expose:**
- Storage Spaces pool health status
- Physical disk health for all 4x Seagate drives
- Disk space for C: and Storage Spaces volume

**Note**: This runs natively on Windows, not in Docker, because it needs direct access to Windows Storage Spaces and disk APIs.

---

## Files to Create/Modify

### 1. `docker-compose.yml`
Add two new services:
- `uptime-kuma`
- `glances`

### 2. `C:/docker-data/scripts/windows-health-server.ps1`
PowerShell HTTP server script that:
- Runs as a background process or scheduled task
- Listens on port 9100
- Returns JSON with Storage Spaces health, disk health, system resources

### 3. Windows Scheduled Task
Create task to start the health server on boot

### 4. Uptime Kuma Configuration
After deployment, configure monitors via web UI at http://localhost:3001

---

## Docker Compose Additions

```yaml
# Health monitoring dashboard
uptime-kuma:
  image: louislam/uptime-kuma:latest
  container_name: uptime-kuma
  restart: unless-stopped
  ports:
    - 3001:3001
  volumes:
    - C:/docker-data/uptime-kuma:/app/data
    - /var/run/docker.sock:/var/run/docker.sock:ro
  environment:
    - TZ=Europe/London

# System resource monitoring
glances:
  image: nicolargo/glances:latest-full
  container_name: glances
  restart: unless-stopped
  pid: host
  ports:
    - 61208:61208
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
  environment:
    - TZ=Europe/London
    - GLANCES_OPT=-w
```

---

## WAN Monitoring (UDM-SE)

Your UDM-SE has a built-in API we can use to monitor both WAN links directly.

**Option A: Simple (Uptime Kuma only)**
- Monitor UDM-SE web interface (https://10.0.0.1)
- Monitor external targets (8.8.8.8, 1.1.1.1) for overall internet health
- Check UDM-SE API endpoint for WAN status using JSON query monitor

**Option B: Detailed (Add UniFi-Poller)**
- Add `unifi-poller` container that pulls metrics from UDM-SE
- Provides detailed WAN1/WAN2 status, throughput, latency
- Exports to InfluxDB or Prometheus (adds complexity)

**Recommended: Option A** - Uptime Kuma can query the UDM-SE API directly:
- `https://10.0.0.1/proxy/network/api/s/default/stat/health` returns WAN status
- Requires UniFi local credentials (will set up as environment variable)

---

## SMART Monitoring Note

Windows Storage Spaces abstracts the physical disks and provides its own health monitoring. The `Get-PhysicalDisk` command already shows:
- `HealthStatus`: Healthy/Warning/Unhealthy
- Individual disk status for all 4x Seagate 16TB drives

We'll create a simple endpoint that exposes this data for Uptime Kuma to monitor.

---

## Post-Deployment Steps

1. Access Uptime Kuma at http://localhost:3001
2. Create account on first login
3. Add monitors for each service (can provide exact configuration)
4. Access Glances at http://localhost:61208
5. Configure Windows Health endpoint monitoring in Uptime Kuma

---

## Implementation Steps

1. **Add Uptime Kuma and Glances to docker-compose.yml**
2. **Create Windows health monitoring script** (`C:/docker-data/scripts/windows-health-server.ps1`)
3. **Register script as Windows scheduled task** (run at startup)
4. **Start new containers** (`docker compose up -d`)
5. **Configure Uptime Kuma** via web UI:
   - Add HTTP monitors for all DockArr services
   - Add ping monitors for WAN (8.8.8.8, 1.1.1.1)
   - Add HTTPS monitor for UDM-SE (https://10.0.0.1)
   - Add JSON monitor for Windows health endpoint (http://host.docker.internal:9100)

---

## Summary

| Component | Purpose | Port | Runs In |
|-----------|---------|------|---------|
| Uptime Kuma | Service health dashboard | 3001 | Docker |
| Glances | Container metrics | 61208 | Docker |
| Windows Health | Storage Spaces/SMART/disk | 9100 | Windows native |
