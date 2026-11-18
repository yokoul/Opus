#!/bin/sh
# Fabrique le zip à publier sur CurseForge : dist/Opus-<version>.zip, avec un seul dossier « Opus » (le nom du .toc).
# git archive ne prend que les fichiers suivis par git (ni .DS_Store, ni __MACOSX, ni ._*), et laisse de côté ce que
# .gitattributes marque export-ignore (ce dossier tools/, les fichiers git).
set -e
cd "$(dirname "$0")/.."
version=$(sed -n 's/^## Version: *//p' Opus.toc | tr -d '\r')
[ -n "$version" ] || { echo "version introuvable dans Opus.toc" >&2; exit 1; }
if [ -n "$(git status --porcelain)" ]; then
	echo "attention : des modifications ne sont pas commitées, elles ne seront pas dans le zip :" >&2
	git status --short >&2
fi
mkdir -p dist
zip="dist/Opus-$version.zip"
rm -f "$zip"
git archive --format=zip --prefix=Opus/ -o "$zip" HEAD
# contrôle : rien d'Apple, et tout sous Opus/
if unzip -Z1 "$zip" | grep -E '(^|/)(\.DS_Store|__MACOSX|\._)' >/dev/null; then echo "le zip contient des fichiers macOS" >&2; exit 1; fi
if unzip -Z1 "$zip" | grep -v '^Opus/' >/dev/null; then echo "le zip contient des fichiers hors du dossier Opus/" >&2; exit 1; fi
unzip -Z1 "$zip"
echo "→ $zip ($(du -h "$zip" | cut -f1)), version $version"
