# monitor-agent

Install Prometheus exporters on any server:

- **Linux** → Node Exporter (`:9100`)
- **Windows** → Windows Exporter (`:9182`)

## Quick install (public one-liner)

Repo: https://github.com/methadevil-ux/monitor-agent

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/methadevil-ux/monitor-agent/main/install-linux.sh | sudo bash
```

Optional custom port:

```bash
curl -fsSL https://raw.githubusercontent.com/methadevil-ux/monitor-agent/main/install-linux.sh | sudo bash -s -- 9100
```

### Windows — PowerShell (Admin)

```powershell
irm https://raw.githubusercontent.com/methadevil-ux/monitor-agent/main/install-windows.ps1 | iex
```

### Windows — CMD only, no PowerShell (Admin)

```bat
curl -fsSL -o %TEMP%\install-windows.cmd https://raw.githubusercontent.com/methadevil-ux/monitor-agent/main/install-windows.cmd && %TEMP%\install-windows.cmd
```

Optional custom port:

```bat
%TEMP%\install-windows.cmd 9182
```

## Local install (no internet raw URL)

### Linux

```bash
sudo bash install-linux.sh
```

### Windows (PowerShell)

```powershell
PowerShell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

### Windows (CMD)

```bat
install-windows.cmd
install-windows.cmd 9182
```

## After install

1. Confirm metrics:
   - Linux: `curl http://127.0.0.1:9100/metrics`
   - Windows: `curl http://127.0.0.1:9182/metrics`
2. Allow inbound TCP from Prometheus (`9100` / `9182`)
3. Add the printed scrape config to Prometheus, then reload

## Versions

| Component | Version | Port |
|---|---|---|
| node_exporter | 1.8.2 | 9100 |
| windows_exporter | 0.29.2 | 9182 |

## Notes

- Scripts download official release binaries from GitHub
- No Prometheus server credentials are embedded
- Windows scripts work on EC2 and on-prem (falls back to local hostname/IP)
- Use `install-windows.cmd` when PowerShell is blocked but CMD is available
