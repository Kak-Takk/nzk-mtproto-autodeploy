<div align="center">

# 🛡️ MTProto FakeTLS Proxy Deployer
**English** | [Русский](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash%205.0+-green.svg)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/Docker-Required-2496ED.svg?logo=docker)](https://www.docker.com/)
[![MTG](https://img.shields.io/badge/mtg-v2-orange.svg)](https://github.com/9seconds/mtg)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420.svg?logo=ubuntu)](https://ubuntu.com/)

<br>

<img src="banner.png" alt="NZK MTPROTO FakeTLS Proxy Deployer" width="800">

**Automated MTProto proxy deployment masked as a regular website (FakeTLS + SNI)**

[Quick Start](#-quick-start) • [Features](#-features) • [Architecture](#architecture) • [FAQ](#-faq)

---

</div>

## ⚡ Quick Start

```bash
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/main/deploy_mt.sh -o deploy_mt.sh && sudo bash deploy_mt.sh
```

> **One command** — and in 30 seconds you get a ready-to-use MTProto proxy on port 443 with FakeTLS masking.

<details>
<summary><b>🔒 Audit-first install (recommended)</b></summary>

```bash
# 1. Download
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/main/deploy_mt.sh -o deploy_mt.sh

# 2. Read the code before running
less deploy_mt.sh

# 3. Run
chmod +x deploy_mt.sh && sudo ./deploy_mt.sh
```

Or install by exact tag (reproducibility):
```bash
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/v0.2.0/deploy_mt.sh -o deploy_mt.sh
```
</details>

🔍 **Verify masking quality (Smoke-Test):**

```bash
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/main/smoke-mtproto.sh -o smoke-mtproto.sh && sudo bash smoke-mtproto.sh
```

---

## 🎯 What Problems Does It Solve?

Deep Packet Inspection (DPI) systems use three main vectors to block proxies. Our script counters each one:

| Attack Vector | What DPI Does | Our Defense |
|---|---|---|
| **Active Probing** | Scans port 443 with fake TLS ClientHello | FakeTLS + Fallback: scanner gets a TLS error or redirect, not proxy fingerprint |
| **Passive Fingerprinting** | Analyses packet sizes, MSS, RTT patterns | MSS=850 + BBR + diverse packet sizes |
| **Statistical Analysis** | Correlates SNI with IP/ASN, long-lived sessions | Trusted RF domains + manual rotation when blocked |

### 💡 Core Principle

Standard MTProto installers simply expose the proxy on an open port — DPI scans it, detects an anomaly, blocks it. We integrate the proxy into your web server via **Nginx SNI routing**: unknown scanners get a TLS error or redirect, while MTProto traffic is routed to the container.
This raises the cost of detection significantly. It’s not perfect stealth (your VPS IP still differs from the RF domain’s real IP), but it’s practical and effective for personal use. Inspired by the same principle behind **VLESS+Reality**.

---

## 🚀 Features

<table>
<tr>
<td width="50%">

### 🔧 Full Automation
- Docker installation (if missing)
- Installing `nginx stream` module
- FakeTLS secret generation
- Container deployment
- Firewall configuration

</td>
<td width="50%">

### 🛡️ Advanced Camouflage (Fallback)
- Protection against Active Probing (DPI scanning)
- Your actual website acts as a shield (Fallback)
- Websites + MTProto share **the same port 443**
- Uses `proxy_protocol` to preserve real client IPs
- Auto-detects and patches existing website configs

</td>
</tr>
<tr>
<td>

### 🛡️ Stealth Profile (v2.0)
- **Smart FakeTLS:** Auto-selects trusted RF domains (`yandex.ru`, `mail.ru`, etc.) for camouflage
- **TCP optimization:** `BBR` + `TCPMSS=850` for natural network profile (no detectable `tc netem`)
- **Timeout protection:** `proxy_buffer_size 16k` prevents connection freezes
- **Manual rotation:** Generates `/root/rotate_fallback.sh` — run manually when blocked to change domain & secret

</td>
<td>

### 📦 Re-execution Management
- Detects existing installation
- Image update (secret preserved)
- Full reinstallation
- Uninstallation with Nginx rollback

</td>
</tr>
<tr>
<td>

### 🔒 Docker Hardening
- `--read-only` container (no disk writes)
- Limits: **256MB RAM**, 1024 PIDs, 0.75 CPU
- `--security-opt no-new-privileges`
- `tmpfs /tmp` instead of disk write
- `ulimit nofile 51200`

</td>
<td>

### 🔬 Built-in Smoke Test
- Full diagnostics: Docker, TLS SNI, iptables, sysctl
- Traffic analysis via `tcpdump` (MSS, packet sizes, jitter)
- Optional `tshark` SNI analysis in ClientHello
- PASS / FAIL / WARN summary counter

</td>
</tr>
</table>

---

## 🧬 Technology DNA

We took the best techniques from top-tier network security tools and combined them into a single solution:

| Technology | Inspired By | How We Apply It |
|---|---|---|
| **FakeTLS + real certificate** | VLESS+Reality | mtg proxies TLS to the real server — DPI sees a genuine certificate |
| **SNI routing (single port)** | Cloak / Trojan-GFW | Nginx Stream multiplexes websites + proxy on :443 |
| **MSS Clamping** | GoodbyeDPI / zapret | `iptables` clamps MSS to 850 — hides server signature from DPI |
| **BBR + sysctl stack** | Enterprise CDN | Kernel tuning: FQ, BBR, tcp_notsent_lowat, keepalive |
| **Profile rotation** | Outline / Shadowsocks | Manual script rotates domain + secret when blocked |
| **Container Hardening** | Docker CIS Benchmark | read-only, no-new-privileges, memory/PIDs limits |

---

<a id="architecture"></a>

## 🏗️ Architecture

### Mode 1 — Direct Connection (Port is free)

```text
+----------+         +-------------------+
| Telegram |---443-->|  MTProto Proxy    |
|  Client  |         |  (Docker: mtg v2) |
+----------+         +-------------------+
                     Network filters see: TLS 1.3 -> yandex.ru / mail.ru (auto-selected RF domain)
```

### Mode 2 — SNI Routing (Nginx on 443)

```text
                               +------------------+
                      +--SNI-->|  Your websites   |
+----------+          | match  |  :8443 + PP      |
|  Client  |---443--->|        +------------------+
|          |          | Nginx
+----------+          | Stream +------------------+
                      | FTLS-->|  MTProto Proxy   |
                      | domain |  :1443 (clean)   |
                      |        +------------------+
                      |        +------------------+
                      +default>|  External site   |
                       (SNI)   |  (fallback)      |
                               +------------------+

DPI sees: standard HTTPS traffic on 443
Your websites: work as before, client IPs are preserved
MTProto: routed by FakeTLS domain SNI, receives clean TCP
Unknown SNI: forwarded to external fallback (e.g. microsoft.com)
```

**Key detail:** the intermediate port `8443` separates `proxy_protocol` (for standard websites) and clean TCP on `1443` (for MTProto). Without this separation, MTProto breaks.

---

## 📋 System Requirements

| Component | Minimum | Recommended |
|---|---|---|
| **OS** | Ubuntu 20.04 / Debian 11 | Ubuntu 22.04+ |
| **RAM** | 256 MB | 512 MB |
| **CPU** | 1 vCPU | 1+ vCPU |
| **Disk** | 1 GB | 2 GB |
| **Network** | Port 443 (open) | — |
| **Docker** | Auto-install | — |

---

## 🔄 Management

When run again, the script offers a menu:

```
╔══════════════════════════════════════════════════════════════╗
║   Existing MTProto proxy installation detected!              ║
╚══════════════════════════════════════════════════════════════╝

  1) Update image     — pull new mtg, recreate container
  2) Reinstall        — from scratch, new secret
  3) Uninstall all    — rollback nginx from backup
  4) Status           — links & logs
  5) Exit
```

### Manual Commands

```bash
# Status
docker ps -f name=mtproto-proxy

# Logs (live)
docker logs -f mtproto-proxy

# Restart
docker restart mtproto-proxy

# Update image
docker pull nineseconds/mtg:2 && docker rm -f mtproto-proxy && sudo bash deploy_mt.sh
```

---

## 🔍 What This Script Changes on Your Server

| Action | Path / Area | Rollback |
|--------|-------------|----------|
| Docker install | `docker.io` (if missing) | `apt remove docker-ce` |
| Container launch | `mtproto-proxy` | `docker rm -f mtproto-proxy` |
| Proxy config | `/root/.mtproto-proxy.conf` (chmod 600) | `rm -f` |
| Rotation script | `/root/rotate_fallback.sh` | `rm -f` |
| sysctl tuning | `/etc/sysctl.d/99-mtproxy-stealth.conf` | `rm -f && sysctl --system` |
| iptables MSS | POSTROUTING + PREROUTING sport/dport 443 | Removed via "Uninstall all" |
| **SNI mode:** Nginx stream | `/etc/nginx/stream_mtproxy.conf` | Restored from backup |
| **SNI mode:** Config patching | `listen 443` → `listen 127.0.0.1:8443 proxy_protocol` | Backup in `/etc/nginx_backup_*` |
| **SNI mode:** Real IP | `/etc/nginx/conf.d/99-mtproto-realip.conf` | `rm -f` |

> Full rollback: run `sudo bash deploy_mt.sh` → option 3 (Uninstall all). Nginx will be restored from a timestamped backup.

---

## ❓ FAQ

<details>
<summary><b>🔒 How secure is this?</b></summary>

- Traffic is masked as legitimate TLS 1.3 requests (trusted high-uptime domains are selected automatically)
- Built-in TCP shaping (MSS clamping + BBR) emulates a standard browser profile
- Traffic analyzers see a standard HTTPS handshake — the cost of detection is significantly raised
- Opening the IP in a browser shows a blank page or your actual website
- The secret is safely stored in `/root/.mtproto-proxy.conf` (chmod 600)
</details>

<details>
<summary><b>🌐 Will my existing websites still work?</b></summary>

Yes. In SNI mode, the script automatically:
- Detects all domains from Nginx configs
- Routes website traffic through an intermediate port
- Preserves real client IPs using `proxy_protocol`
- Creates backups and rolls back on any failure
</details>

<details>
<summary><b>📱 How to connect on a phone?</b></summary>

After installation, the script provides ready-to-use links:
- `tg://proxy?server=...` — opens directly in Telegram
- `https://t.me/proxy?server=...` — via browser
- Manual setup: Settings → Data and Storage → Proxy
</details>

<details>
<summary><b>⚡ How to update mtg?</b></summary>

Simply run the script again and select option 1 (Update image). Your secret and connection links will remain the same.
</details>

<details>
<summary><b>🗑️ How to completely uninstall?</b></summary>

Run the script again and select option 3 (Uninstall all). Nginx configs will be automatically restored from the backup.
</details>



---

## 🔧 Technical Details (v2.0)

- **Engine:** [mtg v2](https://github.com/9seconds/mtg) — Go-implementation of MTProto proxy
- **Containerization:** Docker with `restart: unless-stopped`, memory limits (256MB), PIDs (1024), and `--read-only`
- **Nginx Stream:** SNI routing with `ssl_preread` + `proxy_buffer_size 16k` for stream fragmentation
- **Network Stack (Stealth):** Kernel `sysctl` tuning (FQ, BBR) + `iptables` MSS-clamping at 850 bytes. No artificial `tc netem` delays
- **FakeTLS Domain:** Auto-selects trusted RF domains. In SNI mode, auto-switches to RF domain if your site domain matches (prevents nginx map conflict)
- **Rotation:** `/root/rotate_fallback.sh` manual script for cover domain rotation when blocked
- **Backups:** Timestamped copies of `/etc/nginx` before any modification
- **Config:** `/root/.mtproto-proxy.conf` (chmod 600)

---

## ⚠️ Disclaimer / Safe Use

This script is an open-source network administration tool designed exclusively for educational purposes, network security testing, and privacy protection in open network environments. The author bears no responsibility for the actions of end-users or any violations of local regulations. Please adhere to your regional laws when deploying network nodes.

---

## 📄 License

MIT License. Use freely.

---

<div align="center">

**⭐ If this helped — please leave a star!**

*Made with 🛡️ for a free internet*

</div>
