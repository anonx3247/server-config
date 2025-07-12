# NixOS Server Configuration

This repository contains a NixOS configuration for a mail server with Git hosting (Gitea) and web services.

## Quick Start

1. **Set up your SSH key** (required for root access):
   ```bash
   echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...' > ssh_key
   ```

2. **Run the setup**
   ```bash
   ./setup.sh
   ```

## Individual Scripts

### 1. User Management

Run the interactive user management script:
```bash
./manage-users.sh
```

This script allows you to:
- View current users
- Add new users
- Remove users

All users are stored in `users.txt` (git-ignored).

### 2. Server Deployment

Run the setup script to deploy the server:
```bash
./setup.sh
```

This script will:
- Check for required files (`ssh_key` and `users.txt`)
- Generate `configuration.nix` from the base configuration
- Build and apply the NixOS configuration
- Set up passwords for all users

### 3. DNS Settings Checker

This script allows you to check if your DNS settings are correct
```bash
./check-dns.sh
```

## Services

After successful deployment, the following services will be available:

- **Mail Server**: `mail.lecaillon.com`
  - IMAP: Port 993 (STARTTLS)
  - SMTP: Port 587 (STARTTLS)
  - User emails: `username@lecaillon.com`

- **Git Server**: `git.lecaillon.com`
  - Web interface for Git repositories

- **Web Server**: `anas.lecaillon.com`
  - Static web content

## Configuration

All users created through this system will:
- Have `isNormalUser = true`
- Be able to receive email at `username@lecaillon.com`
- Need to have passwords set during deployment

The system also creates:
- `vmail` system user for mail handling
- `root` user with SSH key access

## DNS Requirements

Make sure to set up DNS records for:
- `mail.lecaillon.com` (A record)
- `git.lecaillon.com` (A record)
- `anas.lecaillon.com` (A record)
- `lecaillon.com` (MX record pointing to mail.lecaillon.com)

## Security

- SSH password authentication is disabled
- Root login only via SSH key
- SSL/TLS certificates managed by ACME (Let's Encrypt)
- Firewall configured with necessary ports only