# Les dépendances pour l'app en prod (on ignore les deps de dev)
FROM composer:lts AS prod-deps
WORKDIR /app
RUN --mount=type=bind,source=./composer.json,target=composer.json \
    --mount=type=bind,source=./composer.lock,target=composer.lock \
    --mount=type=cache,target=/tmp/cache \
    composer install --no-dev --no-interaction

# Les dépendances pour l'app en dev (on inclut toutes les dependances)
FROM composer:lts AS dev-deps
WORKDIR /app
RUN --mount=type=bind,source=./composer.json,target=composer.json \
    --mount=type=bind,source=./composer.lock,target=composer.lock \
    --mount=type=cache,target=/tmp/cache \
    composer install --no-interaction

#Image de base, qui va servir au dev et a la prod
FROM php:8.2-apache AS base
RUN docker-php-ext-install pdo pdo_mysql
COPY ./src /var/www/html

#Image pour instancier des conteneurs de dev (avec watch des sources)
FROM base AS development
COPY ./tests /var/www/html/tests
RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
COPY --from=dev-deps app/vendor/ /var/www/html/vendor

#Image pour le test au moment du build (check app+deps internes)
FROM development AS test
WORKDIR /var/www/html
#Commande spécifique pour tester le coeur de l'app
RUN ./vendor/bin/phpunit tests/HelloWorldTest.php

#Image pour la prod
FROM base AS final
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY --from=prod-deps app/vendor/ /var/www/html/vendor
USER www-data
