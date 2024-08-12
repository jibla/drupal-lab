#!/bin/bash

# Function to check if DDEV is installed
check_ddev() {
  if ! command -v ddev &> /dev/null; then
    echo "DDEV is not installed. Please install DDEV before running this script."
    exit 1
  fi
}

# Function to create a new Drupal project
new_project() {
  local machine_name
  local site_name
  
  read -p "Enter the machine name: " machine_name
  if [[ ! "$machine_name" =~ ^[a-z][-a-z0-9]*$ ]]; then
    echo "Invalid machine name. It must start with a lowercase letter, and can only contain lowercase letters, digits, and hyphens."
    exit 1
  fi

  read -p "Enter the site name: " site_name
  if [ -z "$site_name" ]; then
    echo "Site name cannot be empty."
    exit 1
  fi

  if [ -d "$machine_name" ]; then
    echo "Directory '$machine_name' already exists. Please choose a different machine name."
    exit 1
  fi

  mkdir "$machine_name"
  cd "$machine_name" || exit

  ddev config --project-type=drupal --php-version=8.3 --docroot=web --project-name="$machine_name"
  ddev start
  ddev composer create drupal/recommended-project:^10
  
  # Create config/sync directory above the web folder
  mkdir -p config/sync

  # Create settings.prod.php in web/sites/default/
  cat <<EOL > web/sites/default/settings.prod.php
<?php

/**
 * @file
 * Production-specific configuration file.
 *
 */

// ** Environment Variables Configuration **

// Database settings
\$databases['default']['default'] = [
  'driver' => 'mysql',
  'database' => getenv('DB_NAME') ?: 'drupal',
  'username' => getenv('DB_USER') ?: 'drupal',
  'password' => getenv('DB_PASSWORD') ?: 'secret',
  'host' => getenv('DB_HOST') ?: '127.0.0.1',
  'port' => getenv('DB_PORT') ?: '3306',
  'prefix' => '',
  'collation' => 'utf8mb4_general_ci',
  'charset' => 'utf8mb4',
];

// Trusted host patterns to prevent host header poisoning
\$settings['trusted_host_patterns'] = [
  '^' . preg_quote(getenv('DRUPAL_TRUSTED_HOST_PATTERN') ?: 'www.example.com') . '$',
];

// Hash salt for security
\$settings['hash_salt'] = getenv('DRUPAL_HASH_SALT') ?: 'random-hash-value';

// File system paths
\$settings['file_public_path'] = getenv('DRUPAL_FILE_PUBLIC_PATH') ?: 'sites/default/files';
\$settings['file_private_path'] = getenv('DRUPAL_FILE_PRIVATE_PATH') ?: 'sites/default/files/private';
\$settings['file_temp_path'] = getenv('DRUPAL_FILE_TEMP_PATH') ?: '/tmp';

// Disable development services
\$config['system.logging']['error_level'] = 'hide';
\$config['system.performance']['cache']['page']['max_age'] = 900;
\$config['system.performance']['css']['preprocess'] = TRUE;
\$config['system.performance']['js']['preprocess'] = TRUE;
\$settings['cache']['default'] = 'cache.backend.redis';
\$settings['redis.connection']['interface'] = 'PhpRedis';
\$settings['redis.connection']['host'] = getenv('REDIS_HOST') ?: '127.0.0.1';
\$settings['redis.connection']['port'] = getenv('REDIS_PORT') ?: 6379;

// Set session cookie to be secure
ini_set('session.cookie_secure', '1');

// Reverse proxy settings (if behind a load balancer or reverse proxy)
if (getenv('DRUPAL_REVERSE_PROXY') === 'true') {
  \$settings['reverse_proxy'] = TRUE;
  \$settings['reverse_proxy_addresses'] = explode(',', getenv('DRUPAL_REVERSE_PROXY_ADDRESSES') ?: '');
}

// Other recommended settings for production
\$settings['update_free_access'] = FALSE;
\$settings['allow_authorize_operations'] = FALSE;
\$settings['skip_permissions_hardening'] = TRUE;
EOL

  # Append to web/sites/default/settings.php
  cat <<EOL >> web/sites/default/settings.php
\$settings['config_sync_directory'] = '../config/sync';

if (getenv('DRUPAL_ENVIRONMENT')) {
  \$env = getenv('DRUPAL_ENVIRONMENT');
  \$settings_file = __DIR__ . "/settings.\$env.php";
  if (file_exists(\$settings_file)) {
    include \$settings_file;
  }
} else {
  if (file_exists(__DIR__ . '/settings.local.php')) {
    include __DIR__ . '/settings.local.php';
  }
}
EOL

  # Create .build/Dockerfile
  mkdir -p .build
  cat <<EOL > .build/Dockerfile
# Stage 1: Build stage
FROM php:8.3-fpm-alpine AS build

# Install build dependencies
RUN apk add --no-cache \\
    git \\
    curl \\
    libpng-dev \\
    libjpeg-turbo-dev \\
    libwebp-dev \\
    freetype-dev \\
    libzip-dev \\
    icu-dev \\
    libxml2-dev \\
    oniguruma-dev \\
    unzip \\
    bash

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp && \\
    docker-php-ext-install -j\$(nproc) gd intl zip opcache pdo pdo_mysql mbstring bcmath

# Set working directory
WORKDIR /var/www/html

# Copy only necessary files for Composer
COPY ./composer.json ./composer.lock ./

# Install PHP dependencies (without development packages)
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress

# Copy the entire project to the container
COPY . /var/www/html

# Ensure that settings.php is not overridden and set permissions
RUN chown -R www-data:www-data /var/www/html

# Create the files directory if it doesn't exist and set permissions
RUN mkdir -p sites/default/files && \\
    find sites/default/files -type d -exec chmod 755 {} \; && \\
    find sites/default/files -type f -exec chmod 644 {} \;

# Install Drush globally
RUN composer global require drush/drush

# Add Composer global bin to PATH
ENV PATH="/root/.composer/vendor/bin:\${PATH}"

# Optimize Drupal settings
RUN php -r "opcache_reset();"

# Stage 2: Final stage
FROM php:8.3-fpm-alpine AS runtime

# Copy PHP extensions and configurations from the build stage
COPY --from=build /usr/local/etc/php /usr/local/etc/php
COPY --from=build /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=build /var/www/html /var/www/html

# Set the appropriate permissions
RUN chown -R www-data:www-data /var/www/html

# Set working directory
WORKDIR /var/www/html

# Expose port 9000 for PHP-FPM
EXPOSE 9000

# Start PHP-FPM
CMD ["php-fpm"]
EOL

  # Create .build/.dockerignore
  cat <<EOL > .build/.dockerignore
.ddev/
vendor/
.git/
.github/
node_modules/
tests/
build/
web/sites/default/files/
.env
README.md
.gitattributes
EOL

  # Continue with Drupal installation
  ddev config --update
  ddev composer require drush/drush
  ddev drush site:install --account-name=admin --account-pass=admin --site-name="$site_name" -y

  # Install and enable Gin admin theme
  ddev composer require drupal/gin_toolbar:^1.0@rc drupal/gin:^3.0@rc
  ddev drush theme:enable gin -y
  ddev drush config-set system.theme admin gin -y

  ddev drush cex -y

  echo "New Drupal project '$machine_name' created with Gin admin theme and site name '$site_name'."
}

# Function to remove a Drupal project
remove_project() {
  local project_name=$1
  if [ -z "$project_name" ]; then
    echo "Please provide a project name."
    exit 1
  fi
  ddev stop -a
  ddev rm -a
  rm -rf "$project_name"
  echo "Project $project_name removed."
}

# Function to remove all DDEV projects
remove_all() {
  ddev stop -a
  ddev rm -a
  echo "All DDEV projects removed."
}

# Function to build the Docker image
build_project() {
  local machine_name=$1
  if [ -z "$machine_name" ]; then
    echo "Please provide a image name (you can use : for tagging)."
    exit 1
  fi
  docker build -f .build/Dockerfile -t "${machine_name}" .
  echo "Docker image '${machine_name}' built successfully."
}

# Main script logic
if [ "$#" -lt 1 ]; then
  echo "Usage: drupal-lab {new-project|remove-project|remove-all|build} [project-name]"
  exit 1
fi

# Check if DDEV is installed
check_ddev

# Parse command
case "$1" in
  new-project)
    new_project "$2"
    ;;
  remove-project)
    remove_project "$2"
    ;;
  remove-all)
    remove_all
    ;;
  build)
    build_project "$2"
    ;;
  *)
    echo "Invalid command. Usage: drupal-lab {new-project|remove-project|remove-all|build} [project-name]"
    exit 1
    ;;
esac
