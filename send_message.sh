#!/usr/bin/env bash
##
# Carrega as configurações e o token da API
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

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
