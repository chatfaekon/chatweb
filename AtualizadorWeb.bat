@echo off
echo === Iniciando Deploy Anti-Bloqueio ===

:: 1. Tenta deletar a pasta build manualmente via comando do Windows (mais forte que o flutter clean)
echo Tentando limpar pastas de build...
rd /s /q build 2>nul
rd /s /q .dart_tool 2>nul

:: 2. Segue para o restante do processo
call flutter pub get
call flutter build web --release

echo === Limpando Historico do GitHub (Reset Total) ===
git checkout --orphan latest_branch
git add -A
git commit -m "Deploy: Versao Segura"
git branch -D master 2>nul
git branch -m master
git push origin master --force

echo === Enviando Atualizacao via Shorebird ===
call shorebird patch android

echo === Processo Finalizado com Sucesso! ===
pause