# Renovação de Certificados Let's Encrypt

Este conjunto de scripts automatiza a renovação de certificados SSL/TLS do Let's Encrypt, com suporte para certificados normais e wildcard.
A principal característica é o uso de notificações via Telegram para a validação manual de DNS necessária para certificados wildcard, tornando-o ideal para provedores de DNS que não oferecem uma API.

## Funcionalidades

- **Renovação de Múltiplos Domínios**: Gerencia a renovação de certificados normais e wildcard.
- **Notificação Interativa**: Envia uma mensagem via Telegram com os dados do registro TXT necessário para a validação do DNS de domínios wildcard.
- **Backup e Restauração Automática**:
  - Antes de cada renovação, o certificado atual é salvo em backup.
  - Em caso de falha, o backup mais recente é restaurado.
  - Em execução de produção, se tudo ocorrer bem, os backups são **removidos automaticamente**.
  - Em execução de teste (`--test`), os backups são **mantidos** para conferência.
- **Configuração Centralizada**: Todas as configurações (credenciais, lista de domínios, web server) ficam em um único arquivo `config.sh`.
- **Robustez para Automação (CRON)**:
  - **Arquivo de Log**: Toda a execução é registrada em `cert_renew.log`.
  - **Rotação de Log**: Se o log atingir 1MB, é automaticamente truncado.
  - **Mecanismo de Trava**: Impede execuções simultâneas para evitar conflitos.
- **Modo de Teste Integrado**: Suporte a execução em modo de teste com `--test` para usar o ambiente de staging do Let's Encrypt, evitando impactos em rate limits reais durante depurações.
- **Gestão do Web Server**: Para cada renovação, o serviço configurado (ex.: `nginx`, `apache2`) é parado e reiniciado apenas se estava ativo no início.

## Estrutura dos Arquivos

- `cert_renew.sh`: O script principal que orquestra todo o processo de renovação.
- `send_message.sh`: Contém a função `curl` para enviar mensagens para a API do Telegram.
- `hook_telegram.sh`: Script chamado pelo Certbot durante a validação de DNS para enviar a notificação.
- `config.sh`: **Arquivo de Configuração** com as credenciais, a lista de domínios e o nome do web server.

## Instalação e Configuração

1. **Dependências Necessárias**
   - Acesso root para gerenciar `/etc/letsencrypt` e serviços systemd (ex.: nginx ou apache2).
   - Conta no Telegram com bot configurado para obter `TG_TOKEN` e `TG_CHAT_ID`.
   - `curl` instalado para envios ao Telegram.
   - `certbot` instalado.

2. **Desabilitar Renovações Automáticas do Certbot**
   Para garantir que apenas este script gerencie as renovações:
   ```bash
   sudo systemctl stop certbot.timer && sudo systemctl disable certbot.timer
   ```

3. **Torne os Scripts Executáveis**
   ```bash
   chmod +x *.sh
   ```

4. **Configure o `config.sh`**
   - Abra o arquivo `config.sh`.
   - Preencha os valores para `TG_CHAT_ID` e `TG_TOKEN`.
   - Ajuste `DNS_PROPAGATION_WAIT_MINUTES` se desejar (o padrão é 5 minutos).
   - Edite a variável `WEB_SERVER` com o nome do seu serviço (ex: "nginx").
   - Edite a lista `DOMAINS` com os seus domínios no formato `"domínio|tipo|aliases"` (ex.: `"exemplo.com|wildcard|www.exemplo.com,sub.exemplo.com"`).

## Uso

1. **Execução em modo de teste (staging)**:
   ```bash
   ./cert_renew.sh --test
   ```
   - Usa o ambiente de staging do Let's Encrypt.
   - Gera certificados **inválidos para produção**.
   - Mantém backups mesmo após sucesso.

2. **Execução em produção (manual ou via CRON)**:
   ```bash
   ./cert_renew.sh
   ```
   - Requer root.
   - Se tudo correr bem, remove os backups automaticamente ao final.
   - Se rodado manualmente sem `--test`, o script pedirá confirmação interativa.

3. **Monitoramento do Log**:
   ```bash
   tail -f cert_renew.log
   ```

## Automação com CRON

Para automatizar a execução, adicione uma entrada ao seu crontab - recomenda-se rodar a cada 2 meses.
Não use `--test` em CRON para evitar certificados de teste.

```crontab
# Aviso sobre a renovação no dia 1 às 20h.
0 20 1 */2 * root bash /path/to/cert_renew.sh --alert-cron

# Renovar certificados Let's Encrypt uma vez a cada 2 meses, no dia 2, às 20h.
0 20 2 */2 * root bash /path/to/cert_renew_letsEncrypt/cert_renew.sh
```
