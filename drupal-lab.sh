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


  # Create settings.prod.php in web/sites/default/
  cat <<'EOL' > ./web/sites/default/settings.prod.php
<?php

/**
 * @file
 * Production-specific configuration file.
 *
 */

// ** Environment Variables Configuration **

// Database settings
$databases['default']['default'] = [
  'driver' => 'mysql',
  'database' => getenv('DB_NAME'),
  'username' => getenv('DB_USER'),
  'password' => getenv('DB_PASSWORD'),
  'host' => getenv('DB_HOST'),
  'port' => getenv('DB_PORT'),
  'prefix' => '',
  'collation' => 'utf8mb4_general_ci',
  'charset' => 'utf8mb4',
];

// Trusted host patterns to prevent host header poisoning
$settings['trusted_host_patterns'] = [
  '^' . preg_quote(getenv('DRUPAL_TRUSTED_HOST_PATTERN') ?: 'www.example.com') . '$',
];

// Hash salt for security
$settings['hash_salt'] = getenv('DRUPAL_HASH_SALT') ?: 'random-hash-value';

// File system paths
$settings['file_public_path'] = getenv('DRUPAL_FILE_PUBLIC_PATH') ?: 'sites/default/files';
$settings['file_private_path'] = getenv('DRUPAL_FILE_PRIVATE_PATH') ?: 'sites/default/files/private';
$settings['file_temp_path'] = getenv('DRUPAL_FILE_TEMP_PATH') ?: '/tmp';

// Disable development services
//$config['system.logging']['error_level'] = 'hide';
//$config['system.performance']['cache']['page']['max_age'] = 900;
//$config['system.performance']['css']['preprocess'] = TRUE;
//$config['system.performance']['js']['preprocess'] = TRUE;
//$settings['cache']['default'] = 'cache.backend.redis';
//$settings['redis.connection']['interface'] = 'PhpRedis';
//$settings['redis.connection']['host'] = getenv('REDIS_HOST') ?: '127.0.0.1';
//$settings['redis.connection']['port'] = getenv('REDIS_PORT') ?: 6379;

// Set session cookie to be secure
ini_set('session.cookie_secure', '1');

// Reverse proxy settings (if behind a load balancer or reverse proxy)
if (getenv('DRUPAL_REVERSE_PROXY') === 'true') {
  $settings['reverse_proxy'] = TRUE;
  $settings['reverse_proxy_addresses'] = explode(',', getenv('DRUPAL_REVERSE_PROXY_ADDRESSES') ?: '');
}

// Other recommended settings for production
$settings['update_free_access'] = FALSE;
$settings['allow_authorize_operations'] = FALSE;
$settings['skip_permissions_hardening'] = TRUE;

EOL

  # Append to web/sites/default/settings.php
  cat <<'EOL' >> ./web/sites/default/settings.php
$settings['config_sync_directory'] = '../config/sync';

if (getenv('DRUPAL_ENVIRONMENT')) {
  $env = getenv('DRUPAL_ENVIRONMENT');
  $settings_file = __DIR__ . "/settings.$env.php";
  if (file_exists($settings_file)) {
    include $settings_file;
  }
} else {
  if (file_exists(__DIR__ . '/settings.local.php')) {
    include __DIR__ . '/settings.local.php';
  }
}
EOL

  # Create .build/Dockerfile and Caddyfile
  mkdir -p .build
  cat <<'EOL' > ./.build/Dockerfile
# Stage 1: Build stage
FROM php:8.3-cli AS build

# Install build dependencies and PHP extensions in one RUN command
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libjpeg-dev \
    libwebp-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    libonig-dev \
    unzip \
    bash \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd intl zip opcache pdo pdo_mysql mbstring bcmath

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy Composer files and install dependencies
COPY ./composer.json ./composer.lock ./
ENV COMPOSER_ALLOW_SUPERUSER 1
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress --prefer-dist

# Copy the entire project to the container
COPY . /var/www/html

# Set permissions and create necessary directories
RUN chown -R www-data:www-data /var/www/html \
    && mkdir -p sites/default/files \
    && find sites/default/files -type d -exec chmod 755 {} \; \
    && find sites/default/files -type f -exec chmod 644 {} \;


# Stage 2: Runtime stage with FrankenPHP and Caddy
FROM dunglas/frankenphp:1-php8.3

RUN install-php-extensions \
    apcu \
    gd \
    opcache \
    pdo_mysql \
    zip

COPY --from=drupal:php8.3 /usr/local/etc/php/conf.d/* /usr/local/etc/php/conf.d/
COPY --from=build /var/www/html /opt/drupal
COPY .build/Caddyfile /etc/caddy/Caddyfile

WORKDIR /opt/drupal

ENV PATH=${PATH}:/opt/drupal/vendor/bin
EOL

  # Create .build/Caddyfile
  cat <<'EOL' > ./.build/Caddyfile
{
	{$CADDY_GLOBAL_OPTIONS}

	frankenphp {
		{$FRANKENPHP_CONFIG}
	}

	# https://caddyserver.com/docs/caddyfile/directives#sorting-algorithm
	order php_server before file_server
	order php before file_server
}

{$CADDY_EXTRA_CONFIG}

:80 {
	root * web/
	encode zstd br gzip

	@hiddenPhpFilesRegexp path_regexp \..*/.*\.php$
	error @hiddenPhpFilesRegexp 403

	@notFoundPhpFiles path_regexp /vendor/.*\.php$
	error @notFoundPhpFiles 404

	@notFoundPhpFilesRegexp path_regexp ^/sites/[^/]+/files/.*\.php$
	error @notFoundPhpFilesRegexp 404

	@privateDirRegexp path_regexp ^/sites/.*/private/
	error @privateDirRegexp 403

	@protectedFilesRegexp {
		not path /.well-known*
		path_regexp \.(engine|inc|install|make|module|profile|po|sh|.*sql|theme|twig|tpl(\.php)?|xtmpl|yml)(~|\.sw[op]|\.bak|\.orig|\.save)?$|^/(\..*|Entries.*|Repository|Root|Tag|Template|composer\.(json|lock)|web\.config|yarn\.lock|package\.json)$|^\/#.*#$|\.php(~|\.sw[op]|\.bak|\.orig|\.save)$
	}
	error @protectedFilesRegexp 403

	@static {
		file
		path *.avif *.css *.eot *.gif *.gz *.ico *.jpg *.jpeg *.js *.otf *.pdf *.png *.svg *.ttf *.webp *.woff *.woff2
	}
	header @static Cache-Control "max-age=31536000,public,immutable"

	{$CADDY_SERVER_EXTRA_DIRECTIVES}

	php_server
}
EOL

  # Create .dockerignore
  cat <<'EOL' > ./.dockerignore
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
    printf "Usage: drupal-lab {new-project|remove-project|remove-all|build} [project-name]\n" >&2
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
