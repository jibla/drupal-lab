#!/bin/bash

# Output file for the final script
output_script="drupal-lab.sh"

# Start with the header
cat << 'EOF' > "$output_script"
#!/bin/bash

DDEV="ddev"

check_ddev() {
  if ! command -v "$DDEV" &> /dev/null; then
    printf "DDEV is not installed. Please install DDEV before running this script.\n" >&2
    return 1
  fi
  return 0
}

new_project() {
  local machine_name site_name
  
  read -r -p "Enter the machine name: " machine_name
  if [[ ! "$machine_name" =~ ^[a-z][-a-z0-9]*$ ]]; then
    printf "Invalid machine name. It must start with a lowercase letter, and can only contain lowercase letters, digits, and hyphens.\n" >&2
    return 1
  fi

  read -r -p "Enter the site name: " site_name
  if [[ -z "$site_name" ]]; then
    printf "Site name cannot be empty.\n" >&2
    return 1
  fi
  \$ma
  if [[ -d "$machine_name" ]]; then
    printf "Directory '%s' already exists. Please choose a different machine name.\n" "$machine_name" >&2
    return 1
  fi

  mkdir -p "$machine_name"
  cd "$machine_name" || return 1

  "$DDEV" config --project-type=drupal --php-version=8.3 --docroot=web --project-name="$machine_name"
  "$DDEV" start || return 1
  "$DDEV" composer create drupal/recommended-project:^10 || return 1
  
  mkdir -p config/sync

EOF

# Append settings.prod.php
printf "\n  # Create settings.prod.php in web/sites/default/\n" >> "$output_script"
printf "  cat <<'EOL' > ./web/sites/default/settings.prod.php\n" >> "$output_script"
cat ./build-files/settings.prod.php >> "$output_script"
printf "EOL\n" >> "$output_script"

# Append settings.php modifications
printf "\n  # Append to web/sites/default/settings.php\n" >> "$output_script"
printf "  cat <<'EOL' >> ./web/sites/default/settings.php\n" >> "$output_script"
cat ./build-files/settings.append.php >> "$output_script"
printf "EOL\n" >> "$output_script"

# Append Dockerfile content
printf "\n  # Create .build/Dockerfile and Caddyfile\n" >> "$output_script"
printf "  mkdir -p .build\n" >> "$output_script"
printf "  cat <<'EOL' > ./.build/Dockerfile\n" >> "$output_script"
cat ./build-files/Dockerfile >> "$output_script"
printf "EOL\n" >> "$output_script"

# Append Caddyfile content
printf "\n  # Create .build/Caddyfile\n" >> "$output_script"
printf "  cat <<'EOL' > ./.build/Caddyfile\n" >> "$output_script"
cat ./build-files/Caddyfile >> "$output_script"
printf "EOL\n" >> "$output_script"

# Append .dockerignore content
printf "\n  # Create .dockerignore\n" >> "$output_script"
printf "  cat <<'EOL' > ./.dockerignore\n" >> "$output_script"
cat ./build-files/.dockerignore >> "$output_script"
printf "EOL\n" >> "$output_script"

# Append .gitignore content
printf "\n  # Create .gitignore\n" >> "$output_script"
printf "  cat <<'EOL' > ./.gitignore\n" >> "$output_script"
cat ./build-files/.gitignore >> "$output_script"
printf "\nEOL\n" >> "$output_script"

# Continue with the script
cat << 'EOF' >> "$output_script"
  "$DDEV" config --update || return 1
  "$DDEV" composer require drush/drush || return 1
  "$DDEV" drush site:install --account-name=admin --account-pass=admin --site-name="$site_name" -y || return 1

  "$DDEV" composer require drupal/gin_toolbar:^1.0@rc drupal/gin:^3.0@rc || return 1
  "$DDEV" drush theme:enable gin -y || return 1
  "$DDEV" drush config-set system.theme admin gin -y || return 1

  "$DDEV" drush cex -y || return 1

  printf "New Drupal project '%s' created with Gin admin theme and site name '%s'.\n" "$machine_name" "$site_name"
}

remove_project() {
  local project_name=$1
  if [[ -z "$project_name" ]]; then
    printf "Please provide a project name.\n" >&2
    return 1
  fi
  "$DDEV" stop -a || return 1
  "$DDEV" rm -a || return 1
  rm -rf "$project_name" || return 1
  printf "Project %s removed.\n" "$project_name"
}

remove_all() {
  "$DDEV" stop -a || return 1
  "$DDEV" rm -a || return 1
  printf "All DDEV projects removed.\n"
}

build_project() {
  local machine_name=$1
  if [[ -z "$machine_name" ]]; then
    printf "Please provide an image name (you can use : for tagging).\n" >&2
    return 1
  fi
  
  # Copy Dockerfile and Caddyfile to .build
  cp ./build-files/Dockerfile .build/Dockerfile
  cp ./build-files/Caddyfile .build/Caddyfile

  docker build -f .build/Dockerfile -t "${machine_name}" . || return 1
  printf "Docker image '%s' built successfully.\n" "${machine_name}"
}

main() {
  if [[ "$#" -lt 1 ]]; then
    printf "Usage: drupal-lab {new|remove|remove-all|build} [project-name]\n" >&2
    return 1
  fi

  check_ddev || return 1

  case "$1" in
    new)
      new_project "$2"
      ;;
    remove)
      remove_project "$2"
      ;;
    remove-all)
      remove_all
      ;;
    build)
      build_project "$2"
      ;;
    *)
      printf "Invalid command. Usage: drupal-lab {new|remove|remove-all|build} [project-name]\n" >&2
      return 1
      ;;
  esac
}

main "$@"
EOF

# Make the output script executable
chmod +x "$output_script"
echo "Final script built and saved as $output_script"
