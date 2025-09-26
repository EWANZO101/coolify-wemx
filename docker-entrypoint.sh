#!/bin/sh
set -e

# Colors for better logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info "Starting WemX initialization..."

# Validate required environment variables
if [ -z "$LICENSE_KEY" ]; then
    log_error "LICENSE_KEY environment variable is required!"
    exit 1
fi

if [ -z "$DB_PASSWORD" ]; then
    log_error "DB_PASSWORD environment variable is required!"
    exit 1
fi

# Wait for database with timeout
log_info "Waiting for database connection..."
DB_RETRIES=30
DB_RETRY_COUNT=0

until php -r "
try {
    \$pdo = new PDO('mysql:host=' . \$_ENV['DB_HOST'] . ';port=' . \$_ENV['DB_PORT'], \$_ENV['DB_USERNAME'], \$_ENV['DB_PASSWORD'], [
        PDO::ATTR_TIMEOUT => 5,
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
    ]);
    echo 'Database connection successful' . PHP_EOL;
    exit(0);
} catch (PDOException \$e) {
    echo 'Database connection failed: ' . \$e->getMessage() . PHP_EOL;
    exit(1);
}
"; do
  DB_RETRY_COUNT=$((DB_RETRY_COUNT + 1))
  if [ $DB_RETRY_COUNT -ge $DB_RETRIES ]; then
    log_error "Database connection failed after $DB_RETRIES attempts!"
    exit 1
  fi
  log_warning "Database not ready, waiting... (attempt $DB_RETRY_COUNT/$DB_RETRIES)"
  sleep 5
done

log_success "Database connection established!"

# Generate .env file if it doesn't exist
if [ ! -f .env ]; then
    log_info "Creating .env file from template..."
    cp .env.example .env
else
    log_info "Using existing .env file..."
fi

# Set environment variables in .env
log_info "Configuring environment variables..."
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
sed -i "s|LOG_LEVEL=.*|LOG_LEVEL=${LOG_LEVEL:-info}|g" .env

# Set license key
sed -i "s|LICENSE_KEY=.*|LICENSE_KEY=${LICENSE_KEY}|g" .env
log_success "License key configured"

# Generate APP_KEY if not set
if [ -z "$APP_KEY" ] || ! grep -q "APP_KEY=base64:" .env; then
    log_info "Generating application encryption key..."
    php artisan key:generate --force
    log_success "Application key generated"
else
    log_info "Using existing application key"
fi

# Install dependencies
log_info "Installing Composer dependencies..."
if ! composer install --optimize-autoloader --no-dev --no-interaction; then
    log_error "Failed to install Composer dependencies!"
    exit 1
fi
log_success "Dependencies installed"

# Install WemX
log_info "Installing WemX components..."
if [ ! -f "vendor/wemx/installer/installed" ]; then
    if ! php artisan wemx:install --force; then
        log_error "Failed to install WemX!"
        exit 1
    fi
    log_success "WemX installed"
else
    log_info "WemX already installed, skipping..."
fi

# Create storage link
log_info "Creating storage symbolic link..."
php artisan storage:link || log_warning "Storage link already exists or failed to create"

# Set up database
log_info "Running database migrations..."
if ! php artisan migrate --force; then
    log_error "Database migration failed!"
    exit 1
fi
log_success "Database migrated"

# Enable modules
log_info "Enabling WemX modules..."
php artisan module:enable || log_warning "Module enable command failed or no modules to enable"

# Update license
log_info "Updating license configuration..."
if ! php artisan license:update; then
    log_warning "License update failed - this may be normal on first run"
fi

# Create first admin user if credentials provided
if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ]; then
    log_info "Creating admin user: $ADMIN_EMAIL"
    if php artisan user:create --email="$ADMIN_EMAIL" --password="$ADMIN_PASSWORD" --admin 2>/dev/null; then
        log_success "Admin user created successfully"
    else
        log_warning "Admin user creation failed - user may already exist"
    fi
fi

# Clear and cache config for production
log_info "Optimizing application for production..."
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan route:clear

if [ "$APP_ENV" = "production" ]; then
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    log_success "Application optimized for production"
fi

# Fix permissions
log_info "Setting correct file permissions..."
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html/storage
chmod -R 755 /var/www/html/bootstrap/cache

# Add health check route
log_info "Adding health check routes..."
if ! grep -q "/health" routes/web.php; then
    cat << 'EOF' >> routes/web.php

// Health check endpoints for monitoring
Route::get('/health', function () {
    $checks = [];
    $status = 200;
    
    try {
        DB::connection()->getPdo();
        $checks['database'] = 'ok';
    } catch (Exception $e) {
        $checks['database'] = 'error';
        $status = 503;
    }
    
    $checks['storage'] = is_writable(storage_path()) ? 'ok' : 'error';
    $checks['cache'] = is_writable(storage_path('framework/cache')) ? 'ok' : 'error';
    $checks['wemx'] = file_exists(base_path('vendor/wemx')) ? 'installed' : 'missing';
    
    return response()->json([
        'status' => $status === 200 ? 'healthy' : 'unhealthy',
        'timestamp' => now()->toISOString(),
        'checks' => $checks
    ], $status);
});

Route::get('/ping', function () {
    return response('pong', 200);
});
EOF
    log_success "Health check routes added"
fi

log_success "WemX initialization completed successfully!"
log_info "Application URL: ${APP_URL:-http://localhost}"
log_info "Admin Email: ${ADMIN_EMAIL:-Not configured}"

# Execute the main command
exec "$@"
