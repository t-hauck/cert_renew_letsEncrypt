#!/usr/bin/env bash
##
# Diretório absoluto deste script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar configuração
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
else
  echo "❌ Arquivo config.sh não encontrado."
  echo "   Copie config.git.sh para config.sh e configure seus dados."
  exit 1
fi


# URL com Token da API
TG_URL="https://api.telegram.org/bot${TG_TOKEN}/sendMessage"

# === TELEGRAM FUNCTION ===
send_telegram_message() {
    local message="$1"

    RESPONSE=$(curl -s -X POST \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true" \
        "${TG_URL}")

    # Verifica se a resposta da API indica sucesso.
    # Uma resposta bem-sucedida do Telegram contém "ok":true.
    if ! echo "$RESPONSE" | grep -q '"ok":true'; then
        echo "=================================================="
        echo "  ERRO AO ENVIAR MENSAGEM PARA O TELEGRAM!"
        echo "=================================================="
        echo "Mensagem: $message"
        echo "Resposta da API: $RESPONSE"
        echo "=================================================="
    fi
}
