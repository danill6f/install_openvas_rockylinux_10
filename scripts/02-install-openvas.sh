#!/usr/bin/env bash
# =============================================================================
#  install_openvas_rockylinux_10
#  Etapa 02 - Instalacao do OpenVAS / GVM (Rocky Linux 10.2)
#
#  OBS.: testado somente no Rocky Linux 10.2. Nao garantimos o
#        funcionamento em outras versoes.
#
#  Pre-requisito: scripts/01-prepare-system.sh executado + reboot.
#
#  Blocos:
#    [0] Pre-checagens (root, SO, repositorio Atomicorp, SELinux)
#    [1] Espaco em disco (minimo 50 GB livres)
#    [2] Verificar se o GVM ja esta instalado/configurado
#    [3] Instalar pacote gvm
#    [4] Executar gvm-setup
#    [5] Validar servicos e porta da interface web
#
#  Cada bloco segue: VERIFICA -> APLICA (so se necessario) -> VALIDA
# =============================================================================

set -Eeuo pipefail

# ----------------------------- Configuracao ----------------------------------
MIN_DISK_GB=50
DISK_CHECK_PATH="/var/lib"          # GVM grava feeds e banco em /var/lib
SETUP_MARKER="/var/lib/gvm/.install_openvas_rockylinux_10.setup-done"
GSA_PORT=9392
LOG_FILE="/var/log/openvas-install.log"

NEED_INSTALL=1
NEED_SETUP=1

# ----------------------------- Helpers ---------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()   { echo -e "$(date '+%F %T') $*" | tee -a "$LOG_FILE"; }
info()  { log "${BLUE}[INFO]${NC}  $*"; }
ok()    { log "${GREEN}[ OK ]${NC}  $*"; }
warn()  { log "${YELLOW}[WARN]${NC}  $*"; }
fail()  { log "${RED}[FAIL]${NC}  $*"; exit 1; }
block() { echo; log "${BLUE}==================== $* ====================${NC}"; }

trap 'fail "Erro na linha $LINENO: comando \"$BASH_COMMAND\""' ERR

# =============================================================================
# [0] PRE-CHECAGENS
# =============================================================================
block "[0] Pre-checagens"

[[ $EUID -eq 0 ]] || { echo "Execute como root (sudo)."; exit 1; }
touch "$LOG_FILE"
ok "Executando como root"

. /etc/os-release
[[ "${ID:-}" == "rocky" ]] || fail "SO detectado: ${PRETTY_NAME:-desconhecido}. Este script e para Rocky Linux."
if [[ "${VERSION_ID:-}" != "10.2" ]]; then
    warn "Versao detectada: ${VERSION_ID:-desconhecida}. Script testado somente no Rocky Linux 10.2."
else
    ok "SO: ${PRETTY_NAME}"
fi

if rpm -q atomic-release &>/dev/null || [[ -f /etc/yum.repos.d/atomic.repo ]]; then
    ok "Repositorio Atomicorp presente"
else
    fail "Repositorio Atomicorp nao encontrado. Execute antes: scripts/01-prepare-system.sh"
fi

se_state=$(getenforce 2>/dev/null || echo "Disabled")
if [[ "$se_state" == "Enforcing" ]]; then
    fail "SELinux em Enforcing. Execute scripts/01-prepare-system.sh e reinicie o servidor."
fi
ok "SELinux: $se_state"

# =============================================================================
# [1] ESPACO EM DISCO
# =============================================================================
block "[1] Espaco em disco (minimo ${MIN_DISK_GB} GB)"

mount_point=$(df --output=target "$DISK_CHECK_PATH" | tail -1)
free_gb=$(df --output=avail -BG "$DISK_CHECK_PATH" | tail -1 | tr -dc '0-9')
info "Particao de $DISK_CHECK_PATH: $mount_point | livre: ${free_gb} GB"

if (( free_gb >= MIN_DISK_GB )); then
    ok "Espaco suficiente: ${free_gb} GB livres (minimo ${MIN_DISK_GB} GB)"
else
    fail "Espaco insuficiente em $mount_point: ${free_gb} GB livres. Necessario ${MIN_DISK_GB} GB ou mais."
fi

# =============================================================================
# [2] VERIFICAR SE JA ESTA INSTALADO
# =============================================================================
block "[2] Verificar instalacao existente"

if rpm -q gvm &>/dev/null; then
    ok "Pacote gvm ja instalado ($(rpm -q gvm))"
    NEED_INSTALL=0
else
    info "Pacote gvm nao instalado"
fi

if [[ -f "$SETUP_MARKER" ]]; then
    ok "gvm-setup ja executado em $(cat "$SETUP_MARKER")"
    NEED_SETUP=0
elif [[ $NEED_INSTALL -eq 0 ]] && systemctl is-active --quiet gvmd 2>/dev/null; then
    ok "gvmd ja esta ativo (setup feito anteriormente fora deste script)"
    date '+%F %T' > "$SETUP_MARKER"
    NEED_SETUP=0
else
    info "gvm-setup ainda nao executado"
fi

if [[ $NEED_INSTALL -eq 0 && $NEED_SETUP -eq 0 ]]; then
    ok "OpenVAS/GVM ja instalado e configurado. Pulando para a validacao."
fi

# =============================================================================
# [3] INSTALAR PACOTE GVM
# =============================================================================
block "[3] Instalar gvm"

if [[ $NEED_INSTALL -eq 1 ]]; then
    info "Instalando gvm (pode levar alguns minutos)..."
    dnf install -y gvm | tee -a "$LOG_FILE"
    rpm -q gvm &>/dev/null && ok "gvm instalado ($(rpm -q gvm))" || fail "Falha ao instalar gvm"
else
    ok "Nada a fazer"
fi

command -v gvm-setup >/dev/null || fail "Comando gvm-setup nao encontrado apos a instalacao"

# =============================================================================
# [4] EXECUTAR GVM-SETUP
# =============================================================================
#  O gvm-setup baixa os feeds (NVTs, SCAP, CERT) e cria o banco de dados.
#  Pode levar de 30 minutos a algumas horas, dependendo da conexao.
#  Ele e interativo (ex.: senha do usuario admin), por isso roda direto
#  no terminal, sem redirecionamento.
# =============================================================================
block "[4] gvm-setup"

if [[ $NEED_SETUP -eq 1 ]]; then
    warn "O gvm-setup pode demorar bastante (download dos feeds). Nao interrompa."
    info "Iniciando gvm-setup..."
    rc=0
    gvm-setup || rc=$?
    if [[ $rc -eq 0 ]]; then
        date '+%F %T' > "$SETUP_MARKER"
        ok "gvm-setup concluido"
    else
        fail "gvm-setup terminou com erro (rc=$rc). Verifique a saida acima."
    fi
else
    ok "Nada a fazer"
fi

# =============================================================================
# [5] VALIDACAO
# =============================================================================
block "[5] Validacao"

for svc in redis gvmd gsad ospd-openvas; do
    if ! systemctl list-unit-files "${svc}.service" &>/dev/null || \
       ! systemctl list-unit-files | grep -q "^${svc}\.service"; then
        warn "Servico ${svc} nao encontrado"
        continue
    fi
    if systemctl is-active --quiet "$svc"; then
        ok "Servico ${svc}: ativo"
    else
        warn "Servico ${svc}: $(systemctl is-active "$svc" 2>/dev/null || true)"
    fi
done

if ss -lnt | grep -q ":${GSA_PORT} "; then
    ok "Interface web escutando na porta ${GSA_PORT}"
else
    warn "Porta ${GSA_PORT} nao esta em escuta (o gsad pode ainda estar iniciando)"
fi

# =============================================================================
# RESUMO
# =============================================================================
block "Resumo"
ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
ok "OpenVAS/GVM instalado: $(rpm -q gvm)"
ok "Acesse: https://${ip_addr:-<ip-do-servidor>}:${GSA_PORT}"
info "Log completo: $LOG_FILE"
