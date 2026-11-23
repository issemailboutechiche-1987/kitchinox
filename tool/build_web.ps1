# Version de production : Web Worker du débit (Dart → JS), puis l'application Flutter web.
# Utilisation : powershell -File tool/build_web.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
dart compile js -O2 tool/nest_worker.dart -o web/nest_worker.js
Remove-Item web/nest_worker.js.deps, web/nest_worker.js.map -ErrorAction SilentlyContinue
# police d'icônes complète : la même d'une version à l'autre (une police mise en cache n'a jamais d'icône manquante)
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --no-tree-shake-icons
