#!/bin/sh

# Set strict error handling
set -e

# Check if an argument was provided
if [ $# -eq 0 ]; then
    echo "Error: Missing required parameter."
    echo "Usage: $0 [just recipe] [all|hostname|ip]"
    exit 1
fi

# Get the recipe name
JUST_RECIPE="$1"
# Get the parameter (either "all" or a hostname)
TARGET="$2"

# Function to validate the recipe name
validate_just_recipe() {
  # Store the recipe to validate
  local recipe="$1"
  
  # If no recipe provided, return error
  if [ -z "$recipe" ]; then
    echo "Error: No recipe provided to validate" >&2
    return 1
  fi
  
  # Get the list of valid recipes dynamically
  local valid_recipes=$(just | awk '{print $1}' | grep -vi available)
  
  # Check if the recipe is in the valid recipes list
  # Uses word boundaries to ensure exact match
  if echo "$valid_recipes" | grep -qw "$recipe"; then
    # Recipe is valid
    return 0
  else
    # Recipe is invalid
    echo "Error: Invalid recipe '$recipe'" >&2
    echo "Available recipes:" >&2
    echo "$valid_recipes" | sort | column >&2
    return 1
  fi
}

# Example usage:
if validate_just_recipe "$JUST_RECIPE"; then
  echo "Recipe '$JUST_RECIPE' is valid, proceeding..."
  # Run your command with the validated recipe
#   just "$JUST_RECIPE"
else
  # The function already printed an error message
  exit 1
fi

# Set variables based on the argument
if [ "$TARGET" = "all" ]; then
    IS_GROUP_DEPLOYMENT=true
    echo "Initiating group deployment to all hosts..."
else
    IS_GROUP_DEPLOYMENT=false
    echo "Initiating deployment to single host: $TARGET"
fi

# Check if ansible-playbook command is available
# Use || to prevent set -e from exiting if the command check fails
if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "Error: ansible-playbook command not found."
    echo "Please ensure Ansible is installed and in your PATH."
    exit 1
fi

# Run the appropriate ansible-playbook command
if [ "$IS_GROUP_DEPLOYMENT" = true ]; then
    echo "Running: ansible-playbook -i hosts.ini -e \"remote_command='just $JUST_RECIPE'\" playbooks/just_remote.yml --ask-vault-pass"
    ansible-playbook -i hosts.ini -e "remote_command='just $JUST_RECIPE'" playbooks/just_remote.yml --ask-vault-pass
else
    echo "Running: ansible-playbook -i hosts.ini -e \"remote_command='just $JUST_RECIPE'\" playbooks/just_remote.yml --limit $TARGET --ask-vault-pass"
    ansible-playbook -i hosts.ini -e "remote_command='just $JUST_RECIPE'" playbooks/just_remote.yml --limit "$TARGET" --ask-vault-pass
fi

echo "Deployment complete."