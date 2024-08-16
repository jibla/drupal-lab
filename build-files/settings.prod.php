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

