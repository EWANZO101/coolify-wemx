FROM php:8.3-fpm-alpine

# Install system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    zip \
    unzip \
    git \
    mariadb-client \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    icu-dev \
    oniguruma-dev \
    libxml2-dev \
    autoconf \
    g++ \
    make \
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
RUN printf '# Application Settings\n\
APP_NAME=WemX\n\
APP_ENV=production\n\
APP_DEBUG=false\n\
APP_URL=https://your-domain.com\n\
APP_KEY=\n\
APP_TIMEZONE=UTC\n\
\n\
# License Key (Required)\n\
LICENSE_KEY=your-wemx-license-key\n\
\n\
# Database Configuration\n\
DB_CONNECTION=mysql\n\
DB_HOST=db\n\
DB_PORT=3306\n\
DB_DATABASE=wemx\n\
DB_USERNAME=wemx\n\
DB_PASSWORD=your-secure-database-password\n\
DB_ROOT_PASSWORD=your-secure-root-password\n\
\n\
# Mail Configuration\n\
MAIL_MAILER=smtp\n\
MAIL_HOST=mailhog\n\
MAIL_PORT=1025\n\
MAIL_USERNAME=\n\
MAIL_PASSWORD=\n\
MAIL_ENCRYPTION=\n\
MAIL_FROM_ADDRESS=hello@your-domain.com\n\
MAIL_FROM_NAME=WemX\n\
\n\
# Cache & Session\n\
CACHE_DRIVER=file\n\
SESSION_DRIVER=file\n\
SESSION_LIFETIME=120\n\
SESSION_SECURE_COOKIE=true\n\
\n\
# Misc Settings\n\
LOG_CHANNEL=stack\n\
LOG_LEVEL=debug\n\
BROADCAST_DRIVER=log\n\
FILESYSTEM_DISK=local\n\
QUEUE_CONNECTION=sync\n\
\n\
# Admin User (Optional - for automatic creation)\n\
ADMIN_EMAIL=admin@your-domain.com\n\
ADMIN_PASSWORD=your-secure-admin-password\n\
\n\
# Redis (Optional)\n\
REDIS_HOST=127.0.0.1\n\
REDIS_PASSWORD=null\n\
REDIS_PORT=6379\n\
\n\
# AWS S3 (Optional)\n\
AWS_ACCESS_KEY_ID=\n\
AWS_SECRET_ACCESS_KEY=\n\
AWS_DEFAULT_REGION=us-east-1\n\
AWS_BUCKET=\n\
AWS_USE_PATH_STYLE_ENDPOINT=false\n\
\n\
# Pusher (Optional)\n\
PUSHER_APP_ID=\n\
PUSHER_APP_KEY=\n\
PUSHER_APP_SECRET=\n\
PUSHER_HOST=\n\
PUSHER_PORT=443\n\
PUSHER_SCHEME=https\n\
PUSHER_APP_CLUSTER=mt1\n\
\n\
VITE_PUSHER_APP_KEY="${PUSHER_APP_KEY}"\n\
VITE_PUSHER_HOST="${PUSHER_HOST}"\n\
VITE_PUSHER_PORT="${PUSHER_PORT}"\n\
VITE_PUSHER_SCHEME="${PUSHER_SCHEME}"\n\
VITE_PUSHER_APP_CLUSTER="${PUSHER_APP_CLUSTER}"\n' > .env.example

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
