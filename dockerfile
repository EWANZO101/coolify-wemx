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

# Copy configuration files and .env.example BEFORE creating Laravel project
COPY docker-nginx.conf /etc/nginx/nginx.conf
COPY docker-supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker-php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker-entrypoint.sh /entrypoint.sh
COPY .env.example /tmp/.env.example

# Create Laravel project and install WemX
RUN composer create-project laravel/laravel . --prefer-dist --no-dev \
    && rm -rf database/migrations/* \
    && composer require wemx/installer dev-web --no-dev \
    && cp /tmp/.env.example /var/www/html/.env.example

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
