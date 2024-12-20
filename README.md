# Démo - Containerize a PHP application

Une démo de CI/CD possible d'une application PHP sur la plateforme Docker.

> En cours de construction...

- [Démo - Containerize a PHP application](#démo---containerize-a-php-application)
  - [Tester](#tester)
  - [Workflow](#workflow)
  - [Gestion des différents environnements](#gestion-des-différents-environnements)
  - [Mise en production Côté serveur (rapatrier la nouvelle image)](#mise-en-production-côté-serveur-rapatrier-la-nouvelle-image)
  - [Workflow direct (sans passer par une plateforme CI/CD ni registre)](#workflow-direct-sans-passer-par-une-plateforme-cicd-ni-registre)
  - [Références](#références)


## Tester

On peut réaliser des tests à différentes étapes:

- **Avant** le *build* (tests sources, dev, avant de commit/merge sur le dépôt principal). Mettre en place de l'analyse statique de code, suite de tests, force bonnes pratiques (linter), detect smells, etc. **CI**
- **Pendant** le *build*. Test **app+dépendances internes** (environnement d'exec)
- **Après** le *build*. Test app + dépendances internes + **dep externes** (variables d'env, base de données, API), tests d'intégration/end2end, etc.

Ce qui est *critique* c'est de **tester l'image qui sera déployée** (il faut que ce soit exactement la même !)

## Workflow

1. **Développe** ;
2. **Test** (app) : `docker compose run --build --rm server ./vendor/bin/phpunit tests/HelloWorldTest.php`. Voir le résultat sous forme de status code `echo $?`

> Dans le cas d'un [multi-staged build](https://docs.docker.com/build/building/multi-stage/), si la valeur `target` n'est pas précisée, docker utilise le dernier stage du `Dockerfile`, ici l'image pour la prod.

3. **Build+test en local** (app+deps): `docker build -t php-docker-image-test --progress plain --no-cache --target test .` (ne pas déclencher un CI/CD qui fail pour rien)
4. Si tests passent en local, **commit** puis **push** sur le dépôt *remote*. Un *hook* (merge, commit) déclenche **un job CD** (avec Github Actions ici):
   1. **Build+test**;
   2. **Build+push**;
5. La nouvelle image **est publiée sur un registre**, avec un tag unique, prête à être utilisée;
6. En production, **pull** la nouvelle image et **instancier** de nouveaux conteneurs à partir de celle-ci.
7. La nouvelle version de l'app est déployée !

> Faire un fichier `Makefile` pour simplifier en local, ou un alias ou un script. Vous pouvez aussi utiliser les [hooks de git](https://git-scm.com/book/ms/v2/Customizing-Git-Git-Hooks). L'idée c'est que vous ne devez pas pouvoir échapper à votre procédure. Si vous oubliez de faire quelque chose, la procédure ne doit pas être déclenchée (pas de procédure incomplète) et vous devez être prévenu par un message d'erreur. **Faire en sorte d'avoir le moins de choses auxquelles penser**. Par ex, le push sur le dépôt distant devrait être automatiquement empêché si la suite de tests en local ne passe pas.

## Gestion des différents environnements

> Chaque environnement peut définir des valeurs (variables d'env), des valeurs secretes (clé)

- Une configuration *compose* par environnement. [Plusieurs stratégies](https://docs.docker.com/compose/how-tos/multiple-compose-files/) (include, merge, extends, profiles) :
- Externalisation des variables d'environnement dans fichiers correspondants;
- Chaque fichier compose utilise son fichier d'env;
- Externalisation [des secrets](https://docs.docker.com/engine/swarm/secrets/) (à ne pas placer en variables d'environnement!)

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

1. Placer l'id de la nouvelle image dans un fichier d'env (`.env.x.y.z`) faire un lien symbolique `ln -s .env.x.y.z .env`. Le fichier `.env` pointe sur le dernier fichier `.env.x.y.z` contenant la version de la nouvelle image (nouveau tag) ; 
2. Le fichier `.env` est utilisé par le fichier `compose.yaml`: il utilise et interpole la variable d'environnement pour le tag de l'image à utiliser dans la section `services`: `image: app:${VERSION}`
3. Si besoin d'avancer à la version `x.y.z` :
   1. Créer un nouveau fichier `.env.x.y.z`
   2. Créer le lien symbolique `ln -s .env.x.y.z .env`
   3. Relancer les services basées sur les images mise à jour (`docker compose up`)
4. Si besoin de *rollback*, il suffit de repointer sur le fichier d'env précédent et relancer les conteneurs à partir de l'image précédente (`up`)

> Cette méthode de [liens symboliques](https://fr.wikipedia.org/wiki/Lien_symbolique) est très utilisée et commode. C'est [ce que fait](https://capistranorb.com/documentation/getting-started/rollbacks/) par exemple [l'excellent outil Capistrano](https://capistranorb.com/).

~~~bash
compose.yaml
#Lien symbolique vers la version actuelle
.env -> .env.1.2
#Ancienne version pour le rollback
.env.1
.env.1.1
.env.1.2
~~~

avec `compose.yaml`:

~~~yaml
services:
   app:
      image: ${REGISTRE}/app:${VERSION}
~~~

et les fichiers `.env`, par ex `.env.1.1` :

~~~ini
REGISTRE=vendor
VERSION=1.1
~~~


> **Docker n'est pas un Framework de déploiement**. Docker offre l'artefact et la plateforme standardisés, ne vous dit pas comment vous devez distribuer vos artefacts.

Il existe de nombreuses façons de mettre de déployer des images Docker, à vous d'utiliser la plus adaptée à votre contexte. Ce qui compte c'est que votre mise en production possède les caractéristiques énoncées plus haut (reproductible, déterministe, simple et réversible)

## Workflow direct (sans passer par une plateforme CI/CD ni registre)

1. Développe;
2. Test;
3. Build et test : `docker build --platform <votre plateforme cible> -t app:1 .`
4. Compresse et déploie image via SSH avec scp : `docker save app:1 | gzip | ssh user@ip docker load`

> L'image est directement envoyée via la sortie standard (stout) sur le serveur et chargée depuis l'entrée standard (stdint)

5. Instancie nouveau conteneur: `ssh user@ip docker compose up -d app`


## Références

- [Containerize a PHP application](https://docs.docker.com/guides/php/containerize/), très bon guide sur la mise en place d'un projet Docker avec une pipeline CI/CD