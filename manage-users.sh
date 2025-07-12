#!/usr/bin/env bash

# User Management Script
# Manages users in the users.txt file only

set -e

USERS_FILE="users.txt"

echo "=== User Management ==="
echo

# Create users file if it doesn't exist
if [ ! -f "$USERS_FILE" ]; then
    echo "Creating new users file..."
    touch "$USERS_FILE"
    echo "Created $USERS_FILE"
fi

# Function to show current users
show_users() {
    echo "Current users:"
    if [ -s "$USERS_FILE" ]; then
        cat -n "$USERS_FILE"
    else
        echo "  (no users defined yet)"
    fi
    echo
}

# Function to add a new user
add_user() {
    echo "Enter username (or press Enter to cancel):"
    read -r username
    
    if [ -z "$username" ]; then
        echo "Cancelled."
        return
    fi
    
    # Validate username (basic check)
    if ! echo "$username" | grep -q "^[a-zA-Z][a-zA-Z0-9_-]*$"; then
        echo "Error: Invalid username. Must start with a letter and contain only letters, numbers, underscores, and hyphens."
        return
    fi
    
    # Check if user already exists
    if grep -q "^$username$" "$USERS_FILE" 2>/dev/null; then
        echo "Error: User '$username' already exists."
        return
    fi
    
    # Add user to file
    echo "$username" >> "$USERS_FILE"
    echo "Added user: $username"
}

# Function to remove a user
remove_user() {
    if [ ! -s "$USERS_FILE" ]; then
        echo "No users to remove."
        return
    fi
    
    echo "Enter username to remove (or press Enter to cancel):"
    read -r username
    
    if [ -z "$username" ]; then
        echo "Cancelled."
        return
    fi
    
    # Check if user exists and remove
    if grep -q "^$username$" "$USERS_FILE"; then
        grep -v "^$username$" "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
        echo "Removed user: $username"
    else
        echo "Error: User '$username' not found."
    fi
}

# Main menu loop
while true; do
    show_users
    
    echo "Options:"
    echo "  1) Add a new user"
    echo "  2) Remove a user"
    echo "  3) End User Management"
    echo
    
    read -p "Choose an option (1-3): " choice
    echo
    
    case $choice in
        1)
            add_user
            echo
            ;;
        2)
            remove_user
            echo
            ;;
        3)
            exit 0
            ;;
        *)
            echo "Invalid option. Please choose 1-3."
            echo
            ;;
    esac
done