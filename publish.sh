#!/bin/bash
# Uploads the committed state to GitHub: code to main, the website (web/) to GitHub Pages.
# Remember to bump CACHE in web/app/sw.js when app files change, so installed apps pick up the update.
set -euo pipefail
cd "$(dirname "$0")"
GH="$PWD/.tools/gh"
AUTH=(-c credential.helper= -c "credential.helper=!$GH auth git-credential")
git "${AUTH[@]}" push origin main
git "${AUTH[@]}" subtree push --prefix web origin gh-pages
echo "Online: https://alexx-161.github.io/fokus-wald/"
