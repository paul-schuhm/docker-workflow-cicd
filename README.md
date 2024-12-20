# Démo - Containerize a PHP application

Une démo de CI/CD possible d'une application PHP sur la plateforme Docker.

## Tester

- **Avant** le build (tests sources, dev, avant de commit/merge sur le depot principal). Mettre en place de l'analyse statique de code, suite de tests, force bonne pratiques (linter), detect smells, etc. **CI**
- **Pendant** le build. Test app + dependances (environnement d'exec)
- **Après** le build. Test app + dep + var

## Workflow

1. **Développe** ;
2. **Test** (app) : `docker compose run --build --rm server ./vendor/bin/phpunit tests/HelloWorldTest.php`. Voir le résultat sous forme de status code `echo $?`

> Si `target` non précisée, docker utilise le dernier stage

3. **Build et test en loca**l (app+deps): `docker build -t php-docker-image-test --progress plain --no-cache --target test .` (ne pas déclencher un CI/CD qui fail pour rien)
4. Si tests passent, commit puis **push** sur le depot principal. Un hook (merge, commit) déclenche un job CD



> Faire un fichier Makefile pour simplifier.

## Références

- [Containerize a PHP application](https://docs.docker.com/guides/php/containerize/)