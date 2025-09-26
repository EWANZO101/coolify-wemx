FROM php:8.3-fpm-alpine

# Install system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    zip \
    unzip \
    git \
    mysql-client \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    icu-dev \
    oniguruma-dev \
    libxml2-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        gd \
        zip \
        intl \
        mbstring \
        xml \
        dom \
        curl \
        bcmath

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create application directory
WORKDIR /var/www/html

# Copy composer files first for better layer caching
COPY composer.json composer.lock* ./

# Copy configuration files BEFORE creating Laravel project
COPY docker-nginx.conf /etc/nginx/nginx.conf
COPY docker-supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker-php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker-entrypoint.sh /entrypoint.sh

# Create Laravel project and install WemX
RUN composer create-project laravel/laravel . --prefer-dist --no-dev \
    && rm -rf database/migrations/* \
    && composer require wemx/installer dev-web --no-dev

# Create .env.example with WemX-specific configuration
RUN cat > .env.example << 'EOF'
# Application Settings
APP_NAME=WemX
APP_ENV=production
APP_DEBUG=false
APP_URL=https://your-domain.com
APP_KEY=
APP_TIMEZONE=UTC

# License Key (Required)
LICENSE_KEY=your-wemx-license-key

# Database Configuration
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=wemx
DB_USERNAME=wemx
DB_PASSWORD=your-secure-database-password
DB_ROOT_PASSWORD=your-secure-root-password

# Mail Configuration
MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=
MAIL_FROM_ADDRESS=hello@your-domain.com
MAIL_FROM_NAME=WemX

# Cache & Session
CACHE_DRIVER=file
SESSION_DRIVER=file
SESSION_LIFETIME=120
SESSION_SECURE_COOKIE=true

# Misc Settings
LOG_CHANNEL=stack
LOG_LEVEL=debug
BROADCAST_DRIVER=log
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync

# Admin User (Optional - for automatic creation)
ADMIN_EMAIL=admin@your-domain.com
ADMIN_PASSWORD=your-secure-admin-password

# Redis (Optional)
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# AWS S3 (Optional)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=
AWS_USE_PATH_STYLE_ENDPOINT=false

# Pusher (Optional)
PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_HOST=
PUSHER_PORT=443
PUSHER_SCHEME=https
PUSHER_APP_CLUSTER=mt1

VITE_PUSHER_APP_KEY="${PUSHER_APP_KEY}"
VITE_PUSHER_HOST="${PUSHER_HOST}"
VITE_PUSHER_PORT="${PUSHER_PORT}"
VITE_PUSHER_SCHEME="${PUSHER_SCHEME}"
VITE_PUSHER_APP_CLUSTER="${PUSHER_APP_CLUSTER}"
EOF

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html/storage \
    && chmod -R 755 /var/www/html/bootstrap/cache \
    && chmod +x /entrypoint.sh

# Create required directories
RUN mkdir -p /run/nginx /var/log/nginx /var/log/supervisor

# Health check for Coolify
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Expose port
EXPOSE 80

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
