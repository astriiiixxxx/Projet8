#!/usr/bin/env bash
# =============================================================================
# run-tests.sh
# Script CI/CD d'exécution des tests unitaires pour projets Java (Gradle)
# et Angular (npm). Génère des rapports JUnit XML dans test-results/.
#
# Usage : ./run-tests.sh <chemin_du_projet>
# Exit  : 0 = succès, 1 = échec
# =============================================================================

# ── Sécurité ─────────────────────────────────────────────────────────────────
# -e  : quitte immédiatement si une commande échoue
# -u  : traite les variables non définies comme une erreur
# -o pipefail : un pipe échoue si l'une de ses commandes échoue
set -euo pipefail

# ── Couleurs pour les messages ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Fonctions utilitaires ─────────────────────────────────────────────────────

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERREUR]${NC} $*" >&2; }

# Affiche l'usage et quitte avec le code 1
usage() {
    echo ""
    echo "Usage : $0 <chemin_du_projet>"
    echo ""
    echo "  <chemin_du_projet>  Chemin absolu ou relatif vers la racine du projet"
    echo ""
    echo "Exemples :"
    echo "  $0 ./mon-projet-java"
    echo "  $0 /home/ci/workspace/frontend"
    echo ""
    exit 1
}

# Vérifie qu'une commande est disponible dans le PATH
require_tool() {
    local tool="$1"
    if ! command -v "$tool" &>/dev/null; then
        log_error "Outil requis introuvable : '$tool'"
        log_error "Installez-le et relancez le script."
        exit 1
    fi
    log_info "Outil détecté : $(command -v "$tool")"
}

# =============================================================================
# 1. VALIDATION DES ARGUMENTS
# =============================================================================

if [[ $# -lt 1 ]]; then
    log_error "Argument manquant : chemin du projet requis."
    usage
fi

PROJECT_DIR="$1"

# Vérifie que le chemin existe et est un dossier
if [[ ! -d "$PROJECT_DIR" ]]; then
    log_error "Le dossier spécifié n'existe pas : '$PROJECT_DIR'"
    exit 1
fi

# Résolution du chemin absolu (portable, sans realpath)
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
log_info "Dossier projet : $PROJECT_DIR"

# Dossier de sortie des rapports XML (relatif à la racine du projet)
RESULTS_DIR="$PROJECT_DIR/test-results"

# =============================================================================
# 2. DÉTECTION AUTOMATIQUE DU TYPE DE PROJET
# =============================================================================

PROJECT_TYPE=""

if [[ -f "$PROJECT_DIR/gradlew" ]]; then
    PROJECT_TYPE="java"
    log_info "Projet détecté : Java / Spring Boot (Gradle wrapper trouvé)"
elif [[ -f "$PROJECT_DIR/package.json" ]]; then
    PROJECT_TYPE="angular"
    log_info "Projet détecté : Angular (package.json trouvé)"
else
    log_error "Type de projet non reconnu dans '$PROJECT_DIR'."
    log_error "Attendu : 'gradlew' (Java) ou 'package.json' (Angular)."
    exit 1
fi

# =============================================================================
# 3. NETTOYAGE DES ANCIENS RÉSULTATS
# =============================================================================

log_info "Nettoyage des anciens résultats de tests..."

if [[ -d "$RESULTS_DIR" ]]; then
    rm -rf "$RESULTS_DIR"
    log_info "Dossier supprimé : $RESULTS_DIR"
fi

# Pour Java, nettoyage également du dossier build Gradle
if [[ "$PROJECT_TYPE" == "java" && -d "$PROJECT_DIR/build/test-results" ]]; then
    rm -rf "$PROJECT_DIR/build/test-results"
    log_info "Anciens rapports Gradle supprimés : build/test-results/"
fi

# =============================================================================
# 4. CRÉATION DU DOSSIER test-results/
# =============================================================================

mkdir -p "$RESULTS_DIR"
log_info "Dossier de résultats créé : $RESULTS_DIR"

# =============================================================================
# 5A. EXÉCUTION DES TESTS — PROJET JAVA (GRADLE)
# =============================================================================

run_java_tests() {
    log_info "─────────────────────────────────────────"
    log_info "Vérification des outils Java..."

    # Java doit être disponible dans le PATH
    require_tool "java"

    # Le wrapper gradlew doit être exécutable
    if [[ ! -x "$PROJECT_DIR/gradlew" ]]; then
        log_warn "gradlew n'est pas exécutable — application de chmod +x"
        chmod +x "$PROJECT_DIR/gradlew"
    fi

    log_info "Lancement : ./gradlew clean test"
    log_info "─────────────────────────────────────────"

    # Exécution depuis la racine du projet
    # 'clean' supprime le dossier build avant de compiler et tester
    if (cd "$PROJECT_DIR" && ./gradlew clean test); then
        log_success "Tests Java terminés avec succès."
        TESTS_PASSED=true
    else
        log_error "Échec des tests Java (./gradlew clean test)."
        TESTS_PASSED=false
    fi

    # Copie des rapports JUnit XML générés par Gradle
    # Emplacement par défaut : build/test-results/test/*.xml
    local GRADLE_REPORTS="$PROJECT_DIR/build/test-results/test"

    if [[ -d "$GRADLE_REPORTS" ]]; then
        local xml_count
        xml_count=$(find "$GRADLE_REPORTS" -name "*.xml" | wc -l | tr -d ' ')

        if [[ "$xml_count" -gt 0 ]]; then
            cp "$GRADLE_REPORTS"/*.xml "$RESULTS_DIR/"
            log_info "$xml_count rapport(s) XML copié(s) dans $RESULTS_DIR/"
        else
            log_warn "Aucun fichier XML trouvé dans $GRADLE_REPORTS"
        fi
    else
        log_warn "Dossier de rapports Gradle introuvable : $GRADLE_REPORTS"
        log_warn "Les tests ont peut-être échoué avant de produire des rapports."
    fi

    # Retourne le statut des tests
    [[ "$TESTS_PASSED" == "true" ]]
}

# =============================================================================
# 5B. EXÉCUTION DES TESTS — PROJET ANGULAR (npm)
# =============================================================================

run_angular_tests() {
    log_info "─────────────────────────────────────────"
    log_info "Vérification des outils Node.js / npm..."

    # Node et npm doivent être disponibles
    require_tool "node"
    require_tool "npm"

    log_info "Version Node : $(node --version)"
    log_info "Version npm  : $(npm --version)"

    # Installation des dépendances si node_modules est absent
    if [[ ! -d "$PROJECT_DIR/node_modules" ]]; then
        log_info "node_modules absent — installation des dépendances (npm ci)..."
        # 'npm ci' est préféré à 'npm install' en CI : plus strict et reproductible
        (cd "$PROJECT_DIR" && npm ci)
    else
        log_info "node_modules présent — installation ignorée."
    fi

    log_info "Lancement : npm test (mode CI — sans navigateur, sans watch)"
    log_info "─────────────────────────────────────────"

    # Options CI pour Angular / Karma :
    #   --watch=false      : n'observe pas les fichiers (mode one-shot)
    #   --browsers=ChromeHeadless : pas de navigateur graphique
    #   --reporters=junit  : génère du JUnit XML (nécessite karma-junit-reporter)
    #
    # JUNIT_REPORT_PATH est lu par karma-junit-reporter pour nommer le fichier XML.
    # Si ton projet utilise Jest, adapte les options à la config jest (--ci, --reporters=jest-junit).

    local JUNIT_REPORT_PATH="$RESULTS_DIR/test-results.xml"

    if (
        cd "$PROJECT_DIR"
        JUNIT_REPORT_PATH="$JUNIT_REPORT_PATH" \
        npm test -- \
            --watch=false \
            --browsers=ChromeHeadless \
            --reporters=progress,junit
    ); then
        log_success "Tests Angular terminés avec succès."
        TESTS_PASSED=true
    else
        log_error "Échec des tests Angular (npm test)."
        TESTS_PASSED=false
    fi

    # Vérification que le rapport XML a bien été généré
    # karma-junit-reporter écrit directement dans JUNIT_REPORT_PATH
    if [[ -f "$JUNIT_REPORT_PATH" ]]; then
        log_info "Rapport JUnit XML trouvé : $JUNIT_REPORT_PATH"
    else
        # Certaines configs écrivent dans un sous-dossier par défaut — on cherche
        log_warn "Rapport XML non trouvé à $JUNIT_REPORT_PATH"
        log_warn "Recherche de fichiers XML alternatifs dans le projet..."

        # Recherche dans les emplacements courants (karma-junit-reporter, jest-junit)
        local found_xml
        found_xml=$(find "$PROJECT_DIR" \
            -not -path "*/node_modules/*" \
            -not -path "*/.git/*" \
            -name "*.xml" \
            -newer "$PROJECT_DIR/package.json" \
            2>/dev/null | head -20)

        if [[ -n "$found_xml" ]]; then
            log_info "Fichiers XML trouvés — copie dans $RESULTS_DIR/"
            echo "$found_xml" | while read -r xml_file; do
                cp "$xml_file" "$RESULTS_DIR/"
                log_info "  Copié : $xml_file"
            done
        else
            log_warn "Aucun rapport XML trouvé. Vérifiez la config karma-junit-reporter."
        fi
    fi

    [[ "$TESTS_PASSED" == "true" ]]
}

# =============================================================================
# 6. DISPATCH SELON LE TYPE DE PROJET
# =============================================================================

log_info "═════════════════════════════════════════"
log_info "  Démarrage des tests — type : $PROJECT_TYPE"
log_info "═════════════════════════════════════════"

EXIT_CODE=0

case "$PROJECT_TYPE" in
    java)
        if run_java_tests; then
            log_success "═══════════════════════════════════════"
            log_success "  SUCCÈS : tous les tests Java passent."
            log_success "  Rapports XML : $RESULTS_DIR/"
            log_success "═══════════════════════════════════════"
            EXIT_CODE=0
        else
            log_error "═══════════════════════════════════════"
            log_error "  ÉCHEC : des tests Java ont échoué."
            log_error "  Consultez les rapports : $RESULTS_DIR/"
            log_error "═══════════════════════════════════════"
            EXIT_CODE=1
        fi
        ;;
    angular)
        if run_angular_tests; then
            log_success "═══════════════════════════════════════"
            log_success "  SUCCÈS : tous les tests Angular passent."
            log_success "  Rapports XML : $RESULTS_DIR/"
            log_success "═══════════════════════════════════════"
            EXIT_CODE=0
        else
            log_error "═══════════════════════════════════════"
            log_error "  ÉCHEC : des tests Angular ont échoué."
            log_error "  Consultez les rapports : $RESULTS_DIR/"
            log_error "═══════════════════════════════════════"
            EXIT_CODE=1
        fi
        ;;
esac

# =============================================================================
# 7. RETOUR DU CODE DE SORTIE
# =============================================================================
# Désactivation temporaire de 'set -e' pour que le exit final ne soit pas
# intercepté par le shell parent comme une erreur inattendue.
set +e
exit $EXIT_CODE
