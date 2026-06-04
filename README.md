# Agent CI - Audit automatique de Pull Requests

Agent d'audit intelligent pour vos PRs qui vérifie :
- 🔍 **Review** : bugs, régressions, tests affaiblis, prints oubliés
- 🔒 **Sécurité** : secrets hardcodés, injections SQL, bypass d'auth
- 📝 **Changelog** : fonctions publiques modifiées sans entrée changelog

## Usage local

```bash
# Avec Claude Code (gratuit, pas de clé API requise)
git diff main...ma-branche | ./review-pr.sh

# Avec OpenAI API
export OPENAI_API_KEY="sk-..."
git diff main...ma-branche | ./review-pr.sh
```

## Intégration CI/CD dans vos autres repos

### Étape 1 : Ajouter le secret GitHub

Dans votre autre repo, allez dans **Settings → Secrets and variables → Actions** et ajoutez :
- Nom : `OPENAI_API_KEY`
- Valeur : votre clé OpenAI

### Étape 2 : Créer le workflow

Créez `.github/workflows/pr-review.yml` dans votre autre repo :

```yaml
name: PR Review

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  audit:
    uses: arconycompany/agent-ci/.github/workflows/reusable-pr-review.yml@main
    secrets:
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

C'est tout ! 🎉

### Options avancées

Pour comparer contre une autre branche :

```yaml
jobs:
  audit:
    uses: arconycompany/agent-ci/.github/workflows/reusable-pr-review.yml@main
    with:
      base_ref: 'develop'  # au lieu de 'main'
    secrets:
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

## Résultats

Le workflow :
- ✅ Passe si aucun problème critique
- ❌ Échoue si problèmes critiques détectés
- 📎 Upload `findings.json` et `review_meta.json` comme artifacts
- 💬 Annote les fichiers avec les problèmes trouvés

## Exemples de détection

### Critique (bloque la PR)
- Secrets hardcodés : `API_KEY = "sk-proj-abc123"`
- Injection SQL : `query = f"SELECT * FROM users WHERE id={user_id}"`
- Tests supprimés ou affaiblis

### Warning
- `print()` / `console.log()` en production
- TODO/FIXME dans le code

### Info
- Suggestions de style
- Docstrings manquants

## Coût

Avec `gpt-4o-mini` (par défaut) : ~0.15-0.60 USD par million de tokens.
Une PR typique coûte < $0.01.
