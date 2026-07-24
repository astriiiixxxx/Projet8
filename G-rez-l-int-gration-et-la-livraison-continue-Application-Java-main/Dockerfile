# ============================
# Stage 1 : builder
# ============================
# Image Temurin 21 avec le JDK complet (nécessaire pour compiler, mais inutile
# à l'exécution). Ce stage est jeté à la fin du build, seul le WAR produit sera conservé.
# NB : on utilise la variante "jammy" (Ubuntu/glibc) et non "alpine" pour ce stage.
# Gradle embarque une lib native de surveillance du système de fichiers
# (native-platform-file-events) qui est incompatible avec musl libc (Alpine) et
# provoque un crash SIGSEGV du JVM au démarrage du démon Gradle, en particulier
# sur les hôtes ARM64 (Apple Silicon). Ce problème n'affecte que le build ;
# le stage runner ci-dessous reste sur Alpine sans souci puisqu'il ne fait
# qu'exécuter le WAR avec un JRE standard, sans ces libs natives Gradle.
FROM eclipse-temurin:21-jdk-jammy AS builder

# Dossier de travail dans le conteneur.
WORKDIR /app

# Copie de l'intégralité du projet (code source, build.gradle, gradlew, dossier gradle/...).
# Un découpage plus fin (copier d'abord build.gradle + gradle/ pour profiter du cache
# Docker sur la résolution des dépendances) est possible, mais ici on garde une copie
# simple car le wrapper Gradle télécharge de toute façon les dépendances à chaque build
# tant que le cache n'est pas monté séparément.
COPY . .

# Le wrapper gradlew doit être exécutable (les droits ne sont pas toujours conservés
# lors du clone/copie selon l'OS ou le système de fichiers d'origine).
RUN chmod +x gradlew

# Compile et package l'application en WAR (voir build.gradle : war { enabled = false }
# désactive le WAR "standard" de Gradle, mais bootWar génère bien un WAR exécutable
# via le plugin Spring Boot).
# --no-daemon : désactive le démon Gradle, adapté à un environnement de build
# éphémère (conteneur) où il n'y a pas d'intérêt à garder un process en arrière-plan.
RUN ./gradlew bootWar --no-daemon

# ============================
# Stage 2 : runner
# ============================
# Image Temurin 21 avec uniquement le JRE (pas de compilateur, pas d'outils de build) :
# image plus légère et plus sûre pour l'exécution en production.
FROM eclipse-temurin:21-jre-alpine AS runner

WORKDIR /app

# Copie du WAR généré par le stage builder. Le wildcard *.war évite de coder en dur
# le nom exact du fichier (qui inclut la version du projet, ex. workshop-organizer-0.2.4.war).
# On le renomme app.war pour une commande de lancement stable, indépendante des versions.
COPY --from=builder /app/build/libs/*.war app.war

# Documente le port utilisé par Spring Boot (8080 par défaut, cf. application.properties
# qui ne surcharge pas server.port). Le mapping réel se fait via docker-compose/docker run.
EXPOSE 8080

# Le plugin Spring Boot génère un WAR exécutable (contient un serveur Tomcat embarqué),
# donc "java -jar" fonctionne directement sans serveur d'application externe.
ENTRYPOINT ["java", "-jar", "app.war"]
