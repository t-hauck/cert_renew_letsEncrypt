#!/usr/bin/env bash
##
# === TELEGRAM CONFIG ===
# ATENÇÃO: Preencha as variáveis abaixo com seus dados.
# Este arquivo deve ser incluído no .gitignore e não deve ser versionado.

TG_CHAT_ID=""
TG_TOKEN=""

# Tempo em MINUTOS que o script de hook aguardará pela propagação do DNS.
DNS_PROPAGATION_WAIT_MINUTES=5

# --- CONFIGURAÇÃO DE RENOVAÇÃO ---
# Servidor web para reiniciar (ex: "apache2", "nginx")
WEB_SERVER=""

# Lista de domínios para renovar
# Formato: "dominio|tipo|aliases"
# - dominio: domínio principal (ex: "website.com")
# - tipo: "wildcard" ou "normal"
# - aliases: Opcional para tipo Normal - Subdomínios separados por vírgula (ex: "www.website.com,api.website.com")
DOMAINS=(
  "website.com.br|wildcard|www.website.com.br,cloud.website.com.br,admin.website.com.br"
  "website.net.br|wildcard|www.website.net.br,cloud.website.net.br"
  "website.tec.br|normal|www.website.tec.br"
  "website.tec.br|normal"
)
