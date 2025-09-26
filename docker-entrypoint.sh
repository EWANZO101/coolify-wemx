#!/bin/sh
set -e

echo "Starting WemX initialization..."

# Wait for database to be ready
echo "Waiting for database connection..."
until php -r "
try {
    \$pdo = new PDO('mysql:host=' . \$_ENV['DB_HOST'] . ';port=' . \$_ENV['DB_PORT'], \$_ENV['DB_USERNAME'], \$_ENV['DB_PASSWORD']);
    echo 'Database connection successful' . PHP_EOL;
    exit(0);
} catch (PDOException \$e) {
    echo 'Database connection failed: ' . \$e->getMessage() . PHP_EOL;
    exit(1);
}
"; do
  echo "Database not ready, waiting..."
  sleep 5
done

# Generate .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file..."
    cp .env.example .env
fi

# Set environment variables in .env
echo "Configuring environment..."
sed -i "s|APP_NAME=.*|APP_NAME=${APP_NAME:-WemX}|g" .env
sed -i "s|APP_ENV=.*|APP_ENV=${APP_ENV:-production}|g" .env
sed -i "s|APP_DEBUG=.*|APP_DEBUG=${APP_DEBUG:-false}|g" .env
sed -i "s|APP_URL=.*|APP_URL=${APP_URL:-http://localhost}|g" .env
sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=${APP_TIMEZONE:-UTC}|g" .env

# Database configuration
sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=${DB_CONNECTION:-mysql}|g" .env
sed -i "s|DB_HOST=.*|DB_HOST=${DB_HOST:-db}|g" .env
sed -i "s|DB_PORT=.*|DB_PORT=${DB_PORT:-3306}|g" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_DATABASE:-wemx}|g" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USERNAME:-wemx}|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env

# Mail configuration
sed -i "s|MAIL_MAILER=.*|MAIL_MAILER=${MAIL_MAILER:-smtp}|g" .env
sed -i "s|MAIL_HOST=.*|MAIL_HOST=${MAIL_HOST:-mailhog}|g" .env
sed -i "s|MAIL_PORT=.*|MAIL_PORT=${MAIL_PORT:-1025}|g" .env
sed -i "s|MAIL_USERNAME=.*|MAIL_USERNAME=${MAIL_USERNAME}|g" .env
sed -i "s|MAIL_PASSWORD=.*|MAIL_PASSWORD=${MAIL_PASSWORD}|g" .env
sed -i "s|MAIL_ENCRYPTION=.*|MAIL_ENCRYPTION=${MAIL_ENCRYPTION}|g" .env
sed -i "s|MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-hello@example.com}|g" .env
sed -i "s|MAIL_FROM_NAME=.*|MAIL_FROM_NAME=\"${MAIL_FROM_NAME:-WemX}\"|g" .env

# Other settings
sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=${CACHE_DRIVER:-file}|g" .env
sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=${SESSION_DRIVER:-file}|g" .env
sed -i "s|SESSION_LIFETIME=.*|SESSION_LIFETIME=${SESSION_LIFETIME:-120}|g" .env
sed -i "s|SESSION_SECURE_COOKIE=.*|SESSION_SECURE_COOKIE=${SESSION_SECURE_COOKIE:-true}|g" .env

# Set license key if provided
if [ -n "$LICENSE_KEY" ]; then
    sed -i "s|LICENSE_KEY=.*|LICENSE_KEY=${LICENSE_KEY}|g" .env
fi

# Generate APP_KEY if not set
if [ -z "$APP_KEY" ] || ! grep -q "APP_KEY=base64:" .env; then
    echo "Generating application key..."
    php artisan key:generate --force
fi

# Install dependencies
echo "Installing dependencies..."
composer install --optimize-autoloader --no-dev

# Install WemX
echo "Installing WemX..."
if [ ! -f "vendor/wemx/installer/installed" ]; then
    php artisan wemx:install --force
fi

# Create storage link
echo "Creating storage link..."
php artisan storage:link

# Set up database
echo "Setting up database..."
php artisan migrate --force

# Enable modules
echo "Enabling modules..."
php artisan module:enable

# Update license
if [ -n "$LICENSE_KEY" ]; then
    echo "Setting license key..."
    php artisan license:update
fi

# Create first admin user if needed
if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ]; then
    echo "Creating admin user..."
    php artisan user:create --email="$ADMIN_EMAIL" --password="$ADMIN_PASSWORD" --admin
fi

# Clear and cache config
echo "Optimizing application..."
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan route:clear
php artisan config:cache

# Fix permissions
echo "Setting permissions..."
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html/storage
chmod -R 755 /var/www/html/bootstrap/cache

echo "WemX initialization complete!"

# Execute the main command
exec "$@"