#!/usr/bin/env bash

# DNS Configuration Checker
# Checks if your DNS records are properly configured for the server
#
# Usage: ./check-dns.sh [-y] [domain web_prefix enable_mail enable_git enable_web]
#   -y  Assume yes to all prompts (check all services by default)

set -e

CONFIG_FILE="server_config.conf"

# Check for -y flag
ASSUME_YES=false
if [ "$1" = "-y" ]; then
    ASSUME_YES=true
    shift
fi

echo "=== DNS Configuration Checker ==="
echo

# Function to read configuration from file
read_config_file() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Check if arguments are provided
if [ $# -eq 5 ]; then
    # Arguments provided: domain, web_prefix, enable_mail, enable_git, enable_web
    domain="$1"
    web_domain_prefix="$2"
    enable_mail="$3"
    enable_git="$4"
    enable_web="$5"
    echo "Using provided arguments:"
    echo "  Domain: $domain"
    echo "  Web prefix: $web_domain_prefix"
    echo "  Services: mail=$enable_mail, git=$enable_git, web=$enable_web"
elif read_config_file; then
    # Read from config file
    echo "Using configuration from $CONFIG_FILE:"
    echo "  Domain: $domain"
    echo "  Web prefix: $web_domain_prefix"
    echo "  Services: mail=$enable_mail, git=$enable_git, web=$enable_web"
else
    # Ask for domain name
    echo "Enter your domain name (e.g., example.com):"
    read -r domain

    # Validate domain (basic check)
    if [ -z "$domain" ]; then
        echo "ERROR: Domain name cannot be empty!"
        exit 1
    fi

    if ! echo "$domain" | grep -q "^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$"; then
        echo "ERROR: Invalid domain name format!"
        exit 1
    fi

    echo "Enter the web domain prefix (e.g., web):"
    read -r web_domain_prefix

    if [ -z "$web_domain_prefix" ]; then
        echo "ERROR: Web domain prefix cannot be empty!"
        exit 1
    fi

    if ! echo "$web_domain_prefix" | grep -q "^[a-zA-Z0-9][a-zA-Z0-9_-]*$"; then
        echo "ERROR: Invalid web domain prefix format!"
        exit 1
    fi

    # Ask which services to check
    echo
    echo "Which services would you like to check DNS for?"
    echo

    if [ "$ASSUME_YES" = true ]; then
        echo "Using -y flag: checking all services by default"
        enable_mail="true"
        enable_git="true"
        enable_web="true"
    else
        read -p "Check mail server DNS? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            enable_mail="false"
        else
            enable_mail="true"
        fi

        read -p "Check git server DNS? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            enable_git="false"
        else
            enable_git="true"
        fi

        read -p "Check web server DNS? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            enable_web="false"
        else
            enable_web="true"
        fi
    fi
fi

# If public IP wasn't provided as argument or read from config, ask for it
if [ -z "$public_ip" ]; then
    echo "Enter the public IP of the server:"
    read -r public_ip

    if [ -z "$public_ip" ]; then
        echo "ERROR: Public IP cannot be empty!"
        exit 1
    fi
fi

echo
echo "Checking DNS records for domain: $domain"
echo "Web domain prefix: $web_domain_prefix"
echo "Server IP: $public_ip"
echo

# Function to check A record
check_a_record() {
    local subdomain="$1"
    echo -n "Checking A record for $subdomain.$domain... "
    
    result=$(nix-shell -p bind --command "host -t A $subdomain.$domain" | awk '{print $4}')
    
    if [ "$result" = "$public_ip" ]; then
        echo "✓ Found: $result"
        return 0
    else
        echo "Result: $result"
        echo "✗ Not found"
        return 1
    fi
}

# Function to check MX record
check_mx_record() {
    local domain="$1"
    echo -n "Checking MX record for $domain... "
    
    result=$(nix-shell -p bind --command "host -t mx $domain" | awk '{print $7}')
    
    if [ "$result" = "mail.$domain." ]; then
        echo "✓ Found: $result"
        return 0
    else
        echo "Result: $result"
        echo "✗ Not found"
        return 1
    fi
}

# Function to check TXT record
check_txt_record() {
    local this_domain="$1"
    local expected_content="$2"
    echo -n "Checking TXT record for $this_domain... "
    
    result=$(nix-shell -p bind --command "host -t txt $this_domain" | grep -o '"[^"]*"' | tr -d '\n' | sed 's/" "//')
    
    if [ "$result" = "$expected_content" ]; then
        echo "✓ Found with expected content"
        return 0
    elif [ -z "$expected_content" ]; then
        echo "✓ Found: $result"
        return 0
    else
        echo "Result: $result"
        echo "⚠ Found but content may not match expected"
        return 1
    fi
}

# Check required DNS records
echo "=== Checking Required DNS Records ==="
echo

# Check A records based on enabled services
if [ "$enable_web" = "true" ]; then
    check_a_record $web_domain_prefix || echo "  Please add: $web_domain_prefix.$domain A $public_ip"
fi

if [ "$enable_mail" = "true" ]; then
    check_a_record mail || echo "  Please add: mail.$domain A $public_ip"
fi

if [ "$enable_git" = "true" ]; then
    check_a_record git || echo "  Please add: git.$domain A $public_ip"
fi

echo

# Check MX record only if mail service is enabled
if [ "$enable_mail" = "true" ]; then
    check_mx_record "$domain" || echo "  Please add: $domain MX 10 mail.$domain"
    echo
fi

# Check optional but recommended TXT records only if mail service is enabled
if [ "$enable_mail" = "true" ]; then
    echo "=== Checking Optional TXT Records ==="
    echo

    # SPF record
    check_txt_record "$domain" "\"v=spf1 a:mail.$domain -all\"" || echo "  Recommended: $domain TXT \"v=spf1 a:mail.$domain -all\""

    # DMARC record
    check_txt_record "_dmarc.$domain" "\"v=DMARC1; p=none\"" || echo "  Recommended: _dmarc.$domain TXT \"v=DMARC1; p=none\""

    # DKIM record (may not be available until after server setup)
    get_dkim_record() {
        if [ -f /var/lib/opendkim/keys/mail.txt ]; then
            cat /var/lib/opendkim/keys/mail.txt | grep -o '"[^"]*"' | tr -d '\n' | sed 's/" "//' | sed 's/""//g'
        else
            echo "N/A (DKIM keys not found)"
        fi
    }

    echo -n "Checking DKIM record for mail._domainkey.$domain... "
    check_txt_record "mail._domainkey.$domain" "$(get_dkim_record)" || echo "  Recommended: mail._domainkey.$domain TXT $(get_dkim_record)"
fi

echo
echo "=== DNS Check Complete ==="
echo

# Provide summary
echo "Next steps:"
echo "1. If any records are missing, add them to your DNS provider"
echo "2. Wait for DNS propagation (can take up to 24 hours)"
echo "3. Re-run this script to verify changes"
echo "4. Test your services after DNS propagation"