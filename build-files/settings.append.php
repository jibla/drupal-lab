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
