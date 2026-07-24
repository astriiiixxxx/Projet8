# ============================
# Stage 1 : builder
# ============================
# Image Node 20 en version "alpine" : légère, suffisante pour compiler l'app Angular.
# Ce stage ne sera pas conservé dans l'image finale, seul son résultat (dist/) sera copié.
FROM node:20-alpine AS builder

# Dossier de travail dans le conteneur pour toutes les commandes suivantes.
WORKDIR /app

# On copie uniquement les fichiers de dépendances d'abord (et pas tout le code).
# Cela permet à Docker de mettre en cache la couche "npm ci" tant que ces fichiers
# ne changent pas, même si le code source change ensuite (build plus rapide).
COPY package.json package-lock.json ./

# Installation reproductible des dépendances à partir du lockfile.
# npm ci (au lieu de npm install) : installation stricte, rapide, adaptée à la CI/CD
# (supprime node_modules existant, respecte exactement package-lock.json).
RUN npm ci

# Copie du reste du code source de l'application dans le conteneur.
COPY . .

# Build de production Angular. Le résultat est généré dans dist/olympic-games-starter
# (chemin défini par outputPath dans angular.json).
RUN npm run build

# ============================
# Stage 2 : runner
# ============================
# Image NGINX alpine, version épinglée 1.27 comme demandé dans le README du projet.
# On repart d'une image propre et légère : le SDK Node et les dépendances npm du
# stage précédent ne sont pas embarqués dans l'image finale.
FROM nginx:1.27-alpine AS runner

# La configuration nginx du repo sert les fichiers statiques depuis /app
# et écoute sur le port 80 : on remplace la config par défaut de l'image
# par celle du projet.
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

# Copie des fichiers statiques buildés (HTML/JS/CSS) depuis le stage "builder"
# vers /app, le dossier racine attendu par la configuration nginx.
COPY --from=builder /app/dist/olympic-games-starter /app

# Documente le port sur lequel le conteneur écoute (80, cf. nginx.conf).
# N'ouvre pas réellement le port : c'est le mapping dans docker-compose/docker run
# (-p 80:80) qui rend le service accessible depuis l'hôte.
EXPOSE 80

# Commande de démarrage : NGINX en avant-plan (obligatoire dans un conteneur,
# sinon le process se termine immédiatement et le conteneur s'arrête).
CMD ["nginx", "-g", "daemon off;"]
