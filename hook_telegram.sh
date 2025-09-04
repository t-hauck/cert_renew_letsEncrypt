#!/usr/bin/env bash
## Hook chamado pelo Certbot quando um TXT precisa ser criado no DNS
## Envia a chave via Telegram para configuração manual

source "$(dirname "${BASH_SOURCE[0]}")/send_message.sh"

# Define DNS_PROPAGATION_WAIT_MINUTES como 5 se não existe ou vazia
DNS_PROPAGATION_WAIT_MINUTES=${DNS_PROPAGATION_WAIT_MINUTES:-5}

# Garante que DNS_PROPAGATION_WAIT_MINUTES seja pelo menos 5
if [ -n "$DNS_PROPAGATION_WAIT_MINUTES" ] && [ "$DNS_PROPAGATION_WAIT_MINUTES" -lt 5 ]; then
    DNS_PROPAGATION_WAIT_MINUTES=5
fi

# Certbot fornece essas variáveis
DOMAIN="${CERTBOT_DOMAIN}"
VALIDATION="${CERTBOT_VALIDATION}"

# Nome do registro DNS esperado
RECORD="_acme-challenge.${DOMAIN}"

# Monta a mensagem em HTML
MESSAGE="🔑 Novo desafio DNS para <code>${DOMAIN}</code>

Adicione este registro TXT no seu DNS:

<b>Nome:</b>
<code>${RECORD}</code>

<b>Valor:</b>
<code>${VALIDATION}</code>"

send_telegram_message "$MESSAGE"
send_telegram_message "⏳ Aguardando ${DNS_PROPAGATION_WAIT_MINUTES} minutos para propagação de DNS"

sleep $((DNS_PROPAGATION_WAIT_MINUTES * 60))
