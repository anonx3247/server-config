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

- **Mail Server**: `mail.$domain`
  - IMAP: Port 993 (STARTTLS)
  - SMTP: Port 587 (STARTTLS)
  - User emails: `username@$domain`

- **Git Server**: `git.$domain`
  - Web interface for Git repositories

- **Web Server**: `$web_prefix.$domain`
  - Static web content

## Configuration

All users created through this system will:
- Have `isNormalUser = true`
- Be able to receive email at `username@$domain`
- Need to have passwords set during deployment

The system also creates:
- `vmail` system user for mail handling
- `root` user with SSH key access

## DNS Requirements

Make sure to set up DNS records for:
- `mail.$domain` (A record)
- `git.$domain` (A record)
- `$web_prefix.$domain` (A record)
- `$domain` (MX record pointing to mail.$domain)

## Security

- SSH password authentication is disabled
- Root login only via SSH key
- SSL/TLS certificates managed by ACME (Let's Encrypt)
- Firewall configured with necessary ports only