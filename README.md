# Démo - Stratégies de CI/CD d'une application web conteneurisée

- [Démo - Stratégies de CI/CD d'une application web conteneurisée](#démo---stratégies-de-cicd-dune-application-web-conteneurisée)
  - [Tester](#tester)
  - [Workflow](#workflow)
  - [Gestion des différents environnements](#gestion-des-différents-environnements)
  - [Mise en production côté serveur (rapatrier la nouvelle image)](#mise-en-production-côté-serveur-rapatrier-la-nouvelle-image)
  - [Stratégies de déploiement](#stratégies-de-déploiement)
    - [Méthode 1 : Déploiement manuel réversible basé sur des liens symboliques](#méthode-1--déploiement-manuel-réversible-basé-sur-des-liens-symboliques)
    - [Méthode 2 : *Blue Green deployment*, *zero-downtime*](#méthode-2--blue-green-deployment-zero-downtime)
      - [Principe](#principe)
      - [Procédure](#procédure)
    - [Méthode 3 : déploiement avec le *Rolling Update* de Docker](#méthode-3--déploiement-avec-le-rolling-update-de-docker)
    - [Alternative simple : Workflow direct minimal (sans passer par une plateforme CI/CD ni registre), ni rollback](#alternative-simple--workflow-direct-minimal-sans-passer-par-une-plateforme-cicd-ni-registre-ni-rollback)
  - [Références](#références)

## Tester

Dans une CI :

- **Avant** le *build* (tests sources, dev, avant de commit/merge sur le dépôt principal). Mettre en place de l'analyse statique de code, suite de tests, force bonnes pratiques (linter), detect smells, etc. à placer sur un hook pre-commit. **Test du code (via une image de test)** :
  - environnement identique pour tous
  - isolation complète
  - reproductibilité
- **Après** le *build*. Test app + dépendances internes + **dep externes** (variables d'env, base de données, API), tests d'intégration/end2end, etc. **Test de l'artefact** (**via l'image de prod**)

Ce qui est *critique* c'est de **tester l'image qui sera déployée** (il faut que ce soit exactement la même !)

## Workflow

1. **Développe** ;
2. **Test** en local *via un conteneur*. Voir le résultat sous forme de status code (`echo $?`). A placer par ex sur hook git `pre-commit`. Ici :

~~~bash
#utilise stage development (voir fichier compose)
docker compose run --build --rm server ./vendor/bin/phpunit tests/HelloWorldTest.php
~~~

3. Si tests passent, **commit** puis **push** sur le dépôt *remote*. Un *évènement* (par ex commit sur main, PR + merge) déclenche **un job CI** (avec Github Actions ici):
   1. **Build image de test/test unitaires** (ex: lancement de la suite de tests *pendant* le build d'une image de test);
   2. **Build image de prod**;
   3. **Tests** **externes** sur image prod (contre d'autres conteneurs comme bdd, redis, services ext, etc.)
   4. **Steps supplémentaires** : analyse image (Docker Scout), SonarQube, etc.
4. Si tests passent, **push** nouvelle image sur un registre ave un tag unique (version, hash commit). Fin de la CI.
5. Début de la CD : déploiement de l'image validée (pull + rollout) ! **pull** la nouvelle image et **instancier (run)** de nouveaux conteneurs à partir de celle-ci.
6. Déploiement de la nouvelle version.

> Faire un fichier `Makefile` pour simplifier en local, ou un alias ou un script. Vous pouvez aussi utiliser les [hooks de git](https://git-scm.com/book/ms/v2/Customizing-Git-Git-Hooks). L'idée c'est que vous ne devez pas pouvoir échapper à votre procédure. Si vous oubliez de faire quelque chose, la procédure ne doit pas être déclenchée (pas de procédure incomplète) et vous devez être prévenu par un message d'erreur. **Faire en sorte d'avoir le moins de choses auxquelles penser**. Par ex, le push sur le dépôt distant devrait être automatiquement empêché si la suite de tests en local ne passe pas.

<!-- 
Registres privés : Docker Trusted Register (DTR), Amazon Elastic Container Registry (ECR), etc.
 -->

## Gestion des différents environnements

> Chaque environnement peut définir des valeurs (variables d'env), des valeurs secretes (clé)

- Une configuration *compose* par environnement. [Plusieurs stratégies](https://docs.docker.com/compose/how-tos/multiple-compose-files/) (include, merge, extends, profiles) :
- Externalisation des variables d'environnement dans fichiers correspondants;
- Chaque fichier compose utilise son fichier d'env;
- Externalisation [des secrets](https://docs.docker.com/engine/swarm/secrets/) (à ne pas placer en variables d'environnement!)

## Mise en production côté serveur (rapatrier la nouvelle image)

Une mise en production doit:

- Être **réversible** (*rollback*) ;
- Être **définie par une séquence d'instructions déterministe** ;
- **Idempotente** : déclencher 2 fois la procédure avec les mêmes artefacts revient à le faire une fois ;
- Gérer automatiquement les configurations ;
- Être déclenchée idéalement par **une seule commande/instruction**.

Un exemple :

1. Disposer des fichiers compose sur le serveur de prod, plusieurs solutions :
   1. Cloner le dépôt sur le serveur de prod pour récup les fichiers compose
   2. Créer un dépôt dédié uniquement aux fichiers compose
   3. Copier directement dans le CI/CD les fichiers compose présents dans le dépôt (plusieurs solutions)
   4. Etc.
2. Pull la dernière image puis compose up

## Stratégies de déploiement

### Méthode 1 : Déploiement manuel réversible basé sur des liens symboliques

Pour *pull* dernière image **et être réversible** on peut :

1. Placer l'id de la nouvelle image dans un fichier d'env (`.env.x.y.z`) faire un lien symbolique `ln -s .env.x.y.z .env`. Le fichier `.env` pointe sur le dernier fichier `.env.x.y.z` contenant la version de la nouvelle image (nouveau tag) ;
2. Le fichier `.env` est utilisé par le fichier `compose.yaml`: il utilise et interpole la variable d'environnement pour le tag de l'image à utiliser dans la section `services`: `${REGISTRE}/app:${VERSION}`
3. Si besoin d'avancer à la version `x.y.z` :
   1. **Créer** un nouveau fichier `.env.x.y.z`
   2. **Créer/Refaire** le lien symbolique `ln -sfn .env.x.y.z .env`
   3. **Relancer** les services basées sur les images mise à jour (par ex: `docker compose -f compose.yaml --env-file .env.prod --env-file .env up`)
4. Si besoin de *rollback*, il suffit de **repointer sur le fichier d'env précédent** et relancer les conteneurs à partir de l'image précédente (`compose up`)

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

### Méthode 2 : *Blue Green deployment*, *zero-downtime*

#### Principe

Le [Blue/Green deployment](https://en.wikipedia.org/wiki/Blue%E2%80%93green_deployment) est une stratégie de déploiement visant à réduire au maximum le risque de mise en production d’une nouvelle version avec **aucun downtime** (sans interruption)

**Deux environnements identiques** sont maintenus en production :

- **Blue** : version actuellement en production (stable)
- **Green** : nouvelle version prête à être mise en production
- Base de données **unique** partagée

```text
BLUE APP ─┐
           ├── DB (unique)
GREEN APP ─┘
```

Le trafic est envoyé vers **une seule version à la fois**.

Prérequis : **la CI est passée avec succès**.

#### Procédure

1. (Opt) **Migrer** la base de données (*backward* compatible). La migration supporte *Blue* **et** *Green**
2. **Déployer** *Green*
3. **Basculer** le traffic de *Blue* vers *Green*
4. En cas de problème, **rollback immédiat** vers *Blue*
5. (Opt) Une fois déploiement stabilisé, **migrer** de la base pour retirer support version *Green** (*clean*).

>*Utiliser [le pattern Expand/Contract (Parallel Change)](https://martinfowler.com/bliki/ParallelChange.html)

<!-- ### Entre deux avec rollback de Docker Compose

[le Rolling Update natif de Docker Compose](https://docs.docker.com/reference/compose-file/deploy/)

Si vous voulez le Zero-Downtime sans la complexité des deux dossiers et du script Nginx, il existe une astuce native dans Docker Compose en utilisant la directive rollback_config ou update_config couplée à un nombre de répliques supérieur à 1.

Si votre service app est dupliqué (ex: 2 répliques) derrière un Nginx interne ou un load balancer, Docker peut remplacer les conteneurs un par un :

~~~yaml
services:
  app:
    image: ${REGISTRE}/app:${VERSION}
    deploy:
      replicas: 2
      update_config:
        order: start-first # Démarre le nouveau conteneur AVANT d'arrêter l'ancien
        failure_action: rollback
    healthcheck: # Crucial pour que Docker attende que l'app soit prête
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
~~~

Avec cette configuration, la méthode du lien symbolique via des fichiers `.env` devient *Zero-Downtime*. Lorsque l'on fait `docker compose up -d` :

- Docker démarre le nouveau conteneur (V1.2).
- Il attend que le healthcheck passe au vert.
- Une fois prêt, il coupe l'ancien conteneur (V1.1). -->

### Méthode 3 : déploiement avec le *Rolling Update* de Docker

> À venir...

### Alternative simple : Workflow direct minimal (sans passer par une plateforme CI/CD ni registre), ni rollback

1. Développe;
2. Test;
3. Build et test : `docker build --platform <votre plateforme cible> -t app:1 .`
4. Compresse et déploie image via SSH avec scp : `docker save app:1 | gzip | ssh user@ip docker load`

> L'image est directement envoyée via la sortie standard (stout) sur le serveur et chargée depuis l'entrée standard (stdin)

5. Instancie nouveau conteneur: `ssh user@ip docker compose up -d app`

## Références

- [Containerize a PHP application](https://docs.docker.com/guides/php/containerize/), bon guide sur la mise en place d'un projet Docker avec une pipeline CI/CD
