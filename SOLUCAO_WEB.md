# Guia de Publicação e Correção

Para que as notificações funcionem e os ícones apareçam, você precisa realizar dois procedimentos: o deploy do Backend (Functions) e o rebuild do Frontend (Flutter Web).

## 1. Configurar Notificações (Backend)

Eu já criei a pasta `functions` com todo o código necessário. Você só precisa instalar e enviar para o Google.

1.  Abra um terminal na pasta do projeto.
2.  Entre na pasta functions:
    ```bash
    cd functions
    ```
3.  Instale as dependências:
    ```bash
    npm install
    ```
4.  Volte para a raiz e faça o deploy:
    ```bash
    cd ..
    firebase deploy --only functions
    ```
    *(Se pedir para selecionar o projeto, escolha `chatfaekon-806e9`)*

Isso ativará o envio automático de notificações sempre que uma mensagem for enviada.

---

## 2. Corrigir Ícones "X" (Frontend)

Para garantir que os ícones (Material Icons) carreguem corretamente no endereço `/chatweb/`:

1.  Limpe os arquivos antigos:
    ```bash
    flutter clean
    ```
2.  Gere a versão web final (Release):
    ```bash
    flutter build web --release --base-href /chatweb/
    ```
    *Nota: O comando `--base-href /chatweb/` é crucial para que o site saiba que está numa subpasta.*

3.  Envie todo o conteúdo da pasta `build/web` para o seu repositório GitHub (branch `gh-pages` ou `main`, conforme sua configuração).

4.  **Importante:** Após subir, limpe o cache do seu navegador (Ctrl+Shift+R) ao acessar o site, pois o navegador costuma salvar a versão antiga sem ícones.
