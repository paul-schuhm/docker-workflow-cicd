# Démo - Containerize a PHP application

Une démo de CI/CD possible d'une application PHP sur la plateforme Docker.

## Tester

- **Avant** le build (tests sources, dev, avant de commit/merge sur le dépôt principal). Mettre en place de l'analyse statique de code, suite de tests, force bonnes pratiques (linter), detect smells, etc. **CI**
- **Pendant** le build. Test app + dépendances (environnement d'exec)
- **Après** le build. Test app + dep + var

## Workflow

1. **Développe** ;
2. **Test** (app) : `docker compose run --build --rm server ./vendor/bin/phpunit tests/HelloWorldTest.php`. Voir le résultat sous forme de status code `echo $?`

> Si `target` non précisée, docker utilise le dernier stage

3. **Build et test en local** (app+deps): `docker build -t php-docker-image-test --progress plain --no-cache --target test .` (ne pas déclencher un CI/CD qui fail pour rien)
4. Si tests passent, commit puis **push** sur le dépôt principal. Un hook (merge, commit) déclenche un job CD avec Github Actions ici
   1. Build et test
   2. Build et push
5. La nouvelle image **est publiée sur un registre**, prêt à être déployée
6. En production, **pull** la nouvelle image et **lancer** conteneurs à partir nouvelle image.

> Faire un fichier Makefile pour simplifier.

## Gestion des environnements

- Une configuration *compose* par environnement. [Plusieurs stratégies](https://docs.docker.com/compose/how-tos/multiple-compose-files/) (include, merge, extends, profiles) :
- Externalisation des variables d'environnement dans fichiers correspondants;
- Chaque fichier compose utilise son fichier d'env;

## Mise en production Côté serveur (rapatrier la nouvelle image)

Une mise en production doit:

- Être **réversible** (rollback);
- Être **définie par une séquence d'instructions déterministe**
- **Idempotente** : déclencher 2 fois la procédure avec les mêmes artefacts revient à le faire une fois;
- Gérer automatiquement les configurations
- Être déclenchée idéalement par **une seule commande/instruction**

Un exemple :

1. Avoir les fichiers compose en prod, plusieurs solutions : 
   1. Cloner le dépôt sur le serveur de prod pour récup les fichiers compose
   2. Créer un dépôt dédié uniquement aux fichiers compose
   3. Copier directement dans le CI/CD les fichiers compose présents dans le dépôt (plusieurs solutions)
   4. Etc.
2. Pull la dernière image puis compose up

Pour *pull* dernière image **et être réversible** on peut :

1. Placer l'id de la nouvelle image dans un fichier d'env (.env.id) faire un lien symbolique `ln -s .env.id .env`. Le fichier .env pointe sur le dernier fichier `.env.id` contenant l'id de la nouvelle image
2. Le fichier `.env` est utilisé par le fichier compose
3. Si besoin d'avancer à la version `x.y.z` :
   1. Créer un nouveau fichier `.env.x.y.z`
   2. Créer le lien symbolique `ln -s .env.x.y.z .env`
   3. Relancer les services basées sur les images mise à jour (`docker compose up`)
4. Si besoin de rollback, il suffit de repointer sur le fichier d'env précédent et relancer (up)

> Cette méthode de liens symboliques est très utilisée. C'est ce que fait [l'excellent outil Capistrano](https://capistranorb.com/) sous le capot par exemple.

> **Docker n'est pas un Framework de déploiement**. Docker offre l'artefact et la plateforme standardisés, ne vous dit pas comment vous devez distribuer vos artefacts.

Il existe de nombreuses façons de mettre de déployer des images Docker, à vous d'utiliser la plus adaptée à votre contexte. Ce qui compte c'est que votre mise en production possède les caractéristiques énoncées plus haut (reproductible, déterministe, simple et réversible)

## Références

- [Containerize a PHP application](https://docs.docker.com/guides/php/containerize/)