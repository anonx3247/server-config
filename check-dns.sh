#!/usr/bin/env bash

# DNS Configuration Checker
# Checks if your DNS records are properly configured for the server

set -e

echo "=== DNS Configuration Checker ==="
echo

echo "Enter the public IP of the server:"
read -r public_ip

if [ -z "$public_ip" ]; then
    echo "ERROR: Public IP cannot be empty!"
    exit 1
fi

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


echo
echo "Checking DNS records for domain: $domain"
echo "Web domain prefix: $web_domain_prefix"
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
        echo "✗ Not found"
        return 1
    fi
}

# Function to check MX record
check_mx_record() {
    local domain="$1"
    echo -n "Checking MX record for $domain... "
    
    result=$(nix-shell -p bind --command "host -t mx $domain" | awk '{print $7}')
    
    if [ "$result" = "mx.$domain" ]; then
        echo "✓ Found: $result"
        return 0
    else
        echo "✗ Not found"
        return 1
    fi
}

# Function to check TXT record
check_txt_record() {
    local subdomain="$1"
    local expected_content="$2"
    echo -n "Checking TXT record for $subdomain... "
    
    result=$(nix-shell -p bind --command "host -t txt $subdomain.$domain" | grep -o '"[^"]*"' | tr -d '\n' | sed 's/" "//')
    
    if [ "$result" = "$expected_content" ]; then
        echo "✓ Found with expected content"
        return 0
    elif [ -z "$expected_content" ]; then
        echo "✓ Found: $result"
        return 0
    else
        echo "⚠ Found but content may not match expected: $result"
        return 1
    fi
}

# Check required DNS records
echo "=== Checking Required DNS Records ==="
echo

# Check A records
check_a_record "$web_domain_prefix.$domain" || echo "  Please add: $web_domain_prefix.$domain A $public_ip"
check_a_record "mail.$domain" || echo "  Please add: mail.$domain A $public_ip"
check_a_record "git.$domain" || echo "  Please add: git.$domain A $public_ip"

echo

# Check MX record
check_mx_record "$domain" || echo "  Please add: $domain MX 10 mail.$domain"

echo

# Check optional but recommended TXT records
echo "=== Checking Optional TXT Records ==="
echo

# SPF record
check_txt_record "$domain" "v=spf1" || echo "  Recommended: $domain TXT \"v=spf1 a:mail.$domain -all\""

# DMARC record
check_txt_record "_dmarc.$domain" "v=DMARC1" || echo "  Recommended: _dmarc.$domain TXT \"v=DMARC1; p=none\""

# DKIM record (may not be available until after server setup)

get_dkim_record() {
    cat /var/lib/opendkim/keys/default.txt | grep -o '"[^"]*"' | tr -d '\n' | sed 's/" "//'
}

echo -n "Checking DKIM record for mail._domainkey.$domain... "
check_txt_record "mail._domainkey.$domain" "$(get_dkim_record)" || echo "  Recommended: mail._domainkey.$domain TXT \"$(get_dkim_record)\""

echo
echo "=== DNS Check Complete ==="
echo

# Provide summary
echo "Next steps:"
echo "1. If any records are missing, add them to your DNS provider"
echo "2. Wait for DNS propagation (can take up to 24 hours)"
echo "3. Re-run this script to verify changes"
echo "4. Test your services after DNS propagation"
echo
echo "Common DNS providers:"
echo "- Cloudflare: https://dash.cloudflare.com/"
echo "- Namecheap: https://www.namecheap.com/domains/freedns/"
echo "- GoDaddy: https://www.godaddy.com/help/manage-dns-zone-files-680"
echo "- Google Domains: https://domains.google.com/" 