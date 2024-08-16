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
