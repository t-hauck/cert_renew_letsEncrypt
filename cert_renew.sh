#!/usr/bin/env bash
# ================================================================
# Script de renovação para certificados Let's Encrypt (wildcard + normal)
# ================================================================
# - Remove o certificado antigo ANTES de gerar o novo.
# - Gera um backup do certificado atual em /etc/letsencrypt/live/<domínio>_backup_TIMESTAMP
# - Em caso de erro, restaura automaticamente o último backup.
# - Envia mensagens via Telegram.
# - Recomendado rodar no CRON a cada 60 dias.
#
# Opções suportadas:
#   --test        : Executa em modo de staging (Let's Encrypt falso, sem afetar rate limits).
#   --alert-cron  : Apenas envia notificação via Telegram de que a renovação ocorrerá amanhã.
#
# Exemplo de agendamento CRON:
# ## Aviso um dia antes da execução
#   0 20 1 */2 * root bash /path/to/cert_renew.sh --alert-cron
#
# ## Renovar certificados Lets Encrypt uma vez a cada 2 meses, no dia 2, às 20h.
#   0 20 2 */2 * root bash /path/to/cert_renew.sh
# ================================================================

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

# Diretório de certificados
LIVE_DIR="/etc/letsencrypt/live"

# Configuração de Log e Trava
LOG_FILE="$SCRIPT_DIR/cert_renew.log"
LOCK_FILE="$SCRIPT_DIR/cert_renew.lockfile"

# Redireciona toda a saída para o arquivo de log, mantendo-a no console
exec &> >(tee -a "$LOG_FILE")

# Variáveis Globais - importa configs e função de mensagem
source "$SCRIPT_DIR/send_message.sh"

# Flag global para rastrear sucesso total
ALL_SUCCESS=1

# Processamento de argumentos
## 0 = false, 1 = true
TEST_MODE=0

if [ $# -gt 0 ]; then
    case "$1" in
        --test)
            TEST_MODE=1
            ;;
        --alert-cron)
            # Aviso de renovação futura
            HAS_WILDCARD=0
            COUNT_NORMAL=0
            COUNT_WILDCARD=0
            FIRST_NORMAL=""
            FIRST_WILDCARD=""

            for ENTRY in "${DOMAINS[@]}"; do
                IFS='|' read -r DOMAIN TYPE ALIASES <<< "$ENTRY"
                if [[ "$TYPE" == "wildcard" ]]; then
                    COUNT_WILDCARD=$((COUNT_WILDCARD+1))
                    HAS_WILDCARD=1
                    [[ -z "$FIRST_WILDCARD" ]] && FIRST_WILDCARD="$DOMAIN"
                else
                    COUNT_NORMAL=$((COUNT_NORMAL+1))
                    [[ -z "$FIRST_NORMAL" ]] && FIRST_NORMAL="$DOMAIN"
                fi
            done

            SUMMARY="ℹ️ Renovação automática de certificados será executada amanhã.
Domínios normais: $COUNT_NORMAL"
            [[ -n "$FIRST_NORMAL" ]] && SUMMARY+=" (ex: $FIRST_NORMAL)"

            SUMMARY+="
Domínios wildcard: $COUNT_WILDCARD"
            [[ -n "$FIRST_WILDCARD" ]] && SUMMARY+=" (ex: *.$FIRST_WILDCARD)"

            if [ $HAS_WILDCARD -eq 1 ]; then
                SUMMARY+="

⚠️ Atenção: será necessária ação manual no DNS para os domínios wildcard."
            else
                SUMMARY+="

Nenhuma ação manual é necessária."
            fi

            send_telegram_message "$SUMMARY"
            exit 0
            ;;
        *)
            echo "ERRO: parâmetro não identificado '$1'"
            echo "Uso: $0 [--test | --alert-cron]"
            exit 1
            ;;
    esac
fi

# Função única para gestão de lockfile
manage_lockfile() {
    local ACTION="$1"

    case "$ACTION" in
        "create")
            # Tenta criar o lockfile
            if (set -o noclobber; echo "$$ $(basename "$0") $(date +%Y-%m-%dT%H:%M:%S)" > "$LOCK_FILE") 2>/dev/null; then
                return 0
            else
                local LOCK_INFO LOCK_PID
                LOCK_INFO=$(cat "$LOCK_FILE" 2>/dev/null)
                LOCK_PID=$(echo "$LOCK_INFO" | awk '{print $1}')

                if [[ -n "$LOCK_PID" && -d "/proc/$LOCK_PID" ]]; then
                    echo "ERRO: o script já está em execução. PID: $LOCK_PID - trava encontrada em: $LOCK_FILE"
                    return 1
                else
                    echo "AVISO: lockfile órfão detectado. Recriando.."
                    echo "$$ $(basename "$0") $(date +%Y-%m-%dT%H:%M:%S)" > "$LOCK_FILE" || return 1
                    return 0
                fi
            fi
            ;;
        "remove")
            # Remove o lockfile apenas se pertence a este processo
            if [[ -f "$LOCK_FILE" ]]; then
                local LOCK_PID
                LOCK_PID=$(awk '{print $1}' "$LOCK_FILE")
                if [[ "$LOCK_PID" == "$$" ]]; then
                    rm -f "$LOCK_FILE"
                fi
            fi
            return 0
            ;;
        *)
            send_telegram_message "⚠️ Uso incorreto da função 'manage_lockfile'. Opções suportadas: {create|remove}, Opção passada: $ACTION"
            echo "ERRO: Uso incorreto da função 'manage_lockfile'. Opções suportadas: {create|remove}, Opção passada: $ACTION"
            return 1
            ;;
    esac
}

# Saída com código de erro
exit_with_code() {
    manage_lockfile "remove"

    local EXIT_CODE=${1:-1}
    exit $EXIT_CODE
}

# Remoção de backups
cleanup() {
    # Se log maior que 1MB zerar arquivo com truncate
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 1048576 ]; then
        echo "ℹ️ Log maior que 1MB, limpando $LOG_FILE"
        : > "$LOG_FILE"   # equivalente a truncate -s 0
    fi

    # Remoção de backups e lockfile
    if [ "$TEST_MODE" -eq 1 ]; then
        echo -e "\nScript executado manualmente. Se houverem backups existentes, estes foram mantidos em $LIVE_DIR \n"
        manage_lockfile "remove"
    else
        if [ $ALL_SUCCESS -eq 1 ]; then
            for d in "$LIVE_DIR/"*_backup_*; do
                [ -d "$d" ] && rm -rf "$d"
            done
            send_telegram_message "🧹 Todos os backups removidos após sucesso no script"

            # Limpeza de diretórios órfãos/vazios
            for d in "$LIVE_DIR/"*; do
                if [[ -d "$d" && ! -s "$d/privkey.pem" ]]; then
                    echo "🧹 Removendo diretório vazio ou inválido: $d"
                    rm -rf "$d"
                fi
            done
        else
            send_telegram_message "⚠️ Alguns backups foram mantidos porque houve falhas - verifique em $LIVE_DIR"
        fi

        echo "--- Processo de renovação finalizado em $(date) ---"
        manage_lockfile "remove"
    fi
}

# Verifica se as variáveis existem e têm valor
if [ -z "${TG_CHAT_ID:-}" ] || [ -z "${TG_TOKEN:-}" ] || [ -z "${WEB_SERVER:-}" ] || [ -z "${DOMAINS+x}" ] || [ ${#DOMAINS[@]} -eq 0 ]; then
    echo "ERRO: uma ou mais variáveis críticas não estão definidas ou estão vazias: TG_CHAT_ID | TG_TOKEN | WEB_SERVER | DOMAINS"
    # send_telegram_message "⚠️ ERRO: uma ou mais variáveis críticas não estão definidas ou estão vazias: TG_CHAT_ID | TG_TOKEN | WEB_SERVER | DOMAINS"
    exit_with_code
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: este script deve ser executado como root"
    exit_with_code
fi

# Garante que a limpeza seja executada em qualquer cenário de saída (normal, erro, interrupção)
trap cleanup EXIT INT TERM

# Cria lockfile com verificação embutida
manage_lockfile create || exit_with_code 1

# Status do servidor web no início
WEB_SERVER_STATUS_ON_START=$(systemctl is-active "$WEB_SERVER" || echo "inactive")

# Processamento de argumentos: verifica se --test foi passado
CERTBOT_EXTRA=""
if [ "$TEST_MODE" -eq 1 ]; then
    CERTBOT_EXTRA="--test-cert"
    echo "Modo de teste ativado: Usando --test-cert para ambiente de staging do Let's Encrypt."
else
    # Detecta se está sendo executado interativamente (manual) vs. não-interativo (CRON)
    if [ -t 0 ]; then
        read -r -p "Executando manualmente sem o parâmetro --test. Deseja prosseguir em modo produção? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            echo -e "\n=> execução cancelada pelo usuário"
            exit_with_code
        fi
    fi
fi

web_server() {
    local ACTION=$1
    case "$ACTION" in
        "stop")
            # Verifica se o servidor está rodando antes de parar
            if [[ "$WEB_SERVER_STATUS_ON_START" == "active" ]]; then
                echo "-   $ACTION $WEB_SERVER"
                systemctl stop "$WEB_SERVER" || {
                    ALL_SUCCESS=0
                    echo "ERRO: Falha ao parar $WEB_SERVER"
                    systemctl status --no-pager --full "$WEB_SERVER"
                    send_telegram_message "⚠️ Falha ao parar servidor $WEB_SERVER"
                }
            fi
            ;;
        "start")
            # Reinicia o servidor web somente se estava ativo no início
            if [[ "$WEB_SERVER_STATUS_ON_START" == "active" ]]; then
                echo "-   $ACTION $WEB_SERVER"
                systemctl start "$WEB_SERVER" || {
                    ALL_SUCCESS=0
                    echo "ERRO: Falha ao iniciar $WEB_SERVER"
                    systemctl status --no-pager --full "$WEB_SERVER"
                    send_telegram_message "⚠️ Falha ao iniciar servidor $WEB_SERVER"
                }
            fi
            ;;
        *)
            send_telegram_message "⚠️ Uso incorreto da função 'web_server'. Oopções suportadas: {start|stop}, Opção passada: $ACTION"
            echo "ERRO: Uso incorreto da função 'web_server'. Oopções suportadas: {start|stop}, Opção passada: $ACTION"
            return 1
            ;;
    esac
}

# Funções auxiliares para backup e restore
do_backup() {
    local SRC=$1
    local DEST=$2
    cp -a "$SRC" "$DEST" || {
        ALL_SUCCESS=0
        echo "ERRO: Falha ao criar backup para ${SRC}"
        send_telegram_message "⚠️ Falha ao criar backup para <b>${SRC}</b>"
        return 1
    }
}

do_restore() {
    local SRC=$1
    local DEST=$2

    rm -rf "$DEST" || {
        ALL_SUCCESS=0
        echo "ERRO: Falha ao remover diretório atual para restauração de ${DEST}"
        send_telegram_message "⚠️ Falha ao remover diretório para restauração de <b>${DEST}</b>"
    }

    if cp -a "$SRC" "$DEST"; then
        send_telegram_message "⚠️ Falha na renovação. Backup restaurado: <code>${SRC}</code>"
    else
        ALL_SUCCESS=0
        send_telegram_message "⚠️ Falha ao restaurar backup de <b>${DEST}</b>"
    fi
}

backup_and_delete_cert() {
    local DOMAIN=$1
    local TS
    TS=$(date +%Y%m%d-%H%M%S)
    BACKUP_PATH="$LIVE_DIR/${DOMAIN}_backup_${TS}"

    # Faz backup se existir diretório do domínio
    if [ -d "$LIVE_DIR/${DOMAIN}" ]; then
        echo "📦 Backup do certificado atual: ${DOMAIN} => ${BACKUP_PATH}"
        do_backup "$LIVE_DIR/${DOMAIN}" "$BACKUP_PATH" || return 1
    fi

    # Descobre o nome real do certificado via certbot certificates
    CERT_NAME=$(certbot certificates 2>/dev/null | awk -v d="$DOMAIN" '
    /^[[:space:]]*Certificate Name:/ {name=$3}
    /^[[:space:]]*Domains:/ {
        if ($0 ~ d) {
            print name
            exit
        }
    }
    ')

    if [ -n "$CERT_NAME" ]; then
        echo "🗑 Removendo certificado antigo: $CERT_NAME"
        certbot delete --cert-name "$CERT_NAME" -n || \
            send_telegram_message "⚠️ Falha ao deletar certificado antigo para ${CERT_NAME}"
        # Não marca como falha global, pode ser normal em primeiras execuções
    else
        echo "⚠️ Nenhum certificado ativo encontrado para $DOMAIN"
    fi
}

restore_latest_backup() {
    local DOMAIN=$1
    local BACKUP
    BACKUP=$(find "$LIVE_DIR" -maxdepth 1 -type d -name "${DOMAIN}_backup_*" -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2-)
    # BACKUP=$(ls -td "$LIVE_DIR/"${DOMAIN}_backup_* 2>/dev/null | head -n 1)

    if [ -n "$BACKUP" ]; then
        echo "♻️ Restaurando backup para ${DOMAIN} => $BACKUP"
        do_restore "$BACKUP" "$LIVE_DIR/${DOMAIN}"
    else
        ALL_SUCCESS=0
        echo "ERRO: Nenhum backup encontrado para restaurar ${DOMAIN}"
        send_telegram_message "⚠️ Nenhum backup disponível para <b>${DOMAIN}</b> após falha"
    fi
}

renew_wildcard() {
    local DOMAIN=$1
    local RESULT

    echo "🔒 Renovando domínio wildcard: *.$DOMAIN"
    backup_and_delete_cert "$DOMAIN" || return

    certbot certonly --manual --preferred-challenges=dns \
        --quiet \
        --non-interactive \
        --cert-name "$DOMAIN" \
        --manual-auth-hook "$SCRIPT_DIR/hook_telegram.sh" \
        -d "$DOMAIN" -d "*.$DOMAIN" \
        $CERTBOT_EXTRA
    RESULT=$?

    if [ $RESULT -eq 0 ]; then
        send_telegram_message "✅ Certificado wildcard renovado com sucesso para <b>$DOMAIN</b>"
    else
        restore_latest_backup "$DOMAIN"
        send_telegram_message "❌ Falha ao renovar certificado wildcard para <b>$DOMAIN</b>"
        ALL_SUCCESS=0  # Marca falha global
    fi
}

renew_normal() {
    local DOMAIN=$1
    local ALIASES=$2
    local EXTRA_DOMAINS=()
    local RESULT

    echo "🔒 Renovando domínio $DOMAIN"
    backup_and_delete_cert "$DOMAIN" || return

    if [[ -n "$ALIASES" ]]; then
        IFS=',' read -ra ADDR <<< "$ALIASES"
        for d in "${ADDR[@]}"; do
            EXTRA_DOMAINS+=("-d" "$d")
        done
    fi

    certbot certonly --standalone --preferred-challenges=http \
        --quiet \
        --non-interactive \
        --cert-name "$DOMAIN" \
        -d "$DOMAIN" "${EXTRA_DOMAINS[@]}" \
        $CERTBOT_EXTRA
    RESULT=$?

    if [ $RESULT -eq 0 ]; then
        send_telegram_message "✅ Certificado normal renovado com sucesso para <b>$DOMAIN</b>"
    else
        restore_latest_backup "$DOMAIN"
        send_telegram_message "❌ Falha ao renovar certificado para <b>$DOMAIN</b>"
        ALL_SUCCESS=0  # Marca falha global
    fi
}

# --- Lógica Principal ---
echo "--- Iniciando processo de renovação em $(date) ---"

web_server "stop"

# Loop pelos domínios
for ENTRY in "${DOMAINS[@]}"; do
    IFS='|' read -r DOMAIN TYPE ALIASES <<< "$ENTRY"

    if [[ "$TYPE" == "wildcard" ]]; then
        renew_wildcard "$DOMAIN"
    else
        renew_normal "$DOMAIN" "$ALIASES"
    fi
done

web_server "start"

[[ $ALL_SUCCESS -eq 0 ]] && exit_with_code 1
