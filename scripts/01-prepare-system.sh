#!/usr/bin/env bash
# =============================================================================
#  install_openvas_rockylinux_10
#  Etapa 01 - Preparacao do sistema (Rocky Linux 10)
#
#  Blocos:
#    [0] Pre-checagens (root, SO, rede)
#    [1] Desabilitar IPv6
#    [2] Desabilitar firewalld
#    [3] Desabilitar SELinux
#    [4] Atualizar o sistema
#    [5] Definir DNS (Google + Cloudflare)
#
#  Cada bloco segue: VERIFICA -> APLICA (so se necessario) -> VALIDA
# =============================================================================

set -Eeuo pipefail

# ----------------------------- Configuracao ----------------------------------
DNS_SERVERS="8.8.8.8 8.8.4.4 1.1.1.1"
LOG_FILE="/var/log/openvas-install.log"
BACKUP_DIR="/root/openvas-install-backup/$(date +%Y%m%d-%H%M%S)"
REBOOT_REQUIRED=0

# ----------------------------- Helpers ---------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()   { echo -e "$(date '+%F %T') $*" | tee -a "$LOG_FILE"; }
info()  { log "${BLUE}[INFO]${NC}  $*"; }
ok()    { log "${GREEN}[ OK ]${NC}  $*"; }
warn()  { log "${YELLOW}[WARN]${NC}  $*"; }
fail()  { log "${RED}[FAIL]${NC}  $*"; exit 1; }
block() { echo; log "${BLUE}==================== $* ====================${NC}"; }

backup() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    mkdir -p "$BACKUP_DIR"
    cp -a "$f" "$BACKUP_DIR/"
    info "Backup de $f -> $BACKUP_DIR/"
}

trap 'fail "Erro na linha $LINENO: comando \"$BASH_COMMAND\""' ERR

# =============================================================================
# [0] PRE-CHECAGENS
# =============================================================================
block "[0] Pre-checagens"

[[ $EUID -eq 0 ]] || { echo "Execute como root (sudo)."; exit 1; }
touch "$LOG_FILE"
ok "Executando como root"

[[ -f /etc/os-release ]] || fail "/etc/os-release nao encontrado"
. /etc/os-release
if [[ "${ID:-}" != "rocky" ]]; then
    fail "SO detectado: ${PRETTY_NAME:-desconhecido}. Este script e para Rocky Linux."
fi
if [[ "${VERSION_ID%%.*}" != "10" ]]; then
    warn "Versao detectada: ${VERSION_ID}. Script testado para Rocky Linux 10."
else
    ok "SO: ${PRETTY_NAME}"
fi

command -v nmcli >/dev/null || fail "nmcli (NetworkManager) nao encontrado"
command -v dnf   >/dev/null || fail "dnf nao encontrado"
ok "Ferramentas basicas presentes (dnf, nmcli)"

if ping -c1 -W3 8.8.8.8 &>/dev/null; then
    ok "Conectividade com a internet (ICMP 8.8.8.8)"
else
    warn "Sem resposta de ping para 8.8.8.8 (pode ser bloqueio de ICMP)"
fi

# =============================================================================
# [1] DESABILITAR IPv6
# =============================================================================
block "[1] Desabilitar IPv6"

SYSCTL_IPV6="/etc/sysctl.d/99-disable-ipv6.conf"
current_ipv6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "N/A")
info "Estado atual: net.ipv6.conf.all.disable_ipv6 = ${current_ipv6}"

if [[ "$current_ipv6" == "1" && -f "$SYSCTL_IPV6" ]]; then
    ok "IPv6 ja esta desabilitado e persistente. Nada a fazer."
else
    cat > "$SYSCTL_IPV6" <<'EOF'
# Gerado por install_openvas_rockylinux_10
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl --system >/dev/null
    info "Arquivo $SYSCTL_IPV6 criado e aplicado"
fi

# NetworkManager tambem deve ignorar IPv6 nas conexoes ativas
while IFS=: read -r con dev; do
    [[ -z "$dev" || "$dev" == "lo" ]] && continue
    method=$(nmcli -g ipv6.method con show "$con")
    if [[ "$method" != "disabled" ]]; then
        nmcli con mod "$con" ipv6.method disabled
        info "Conexao '$con' ($dev): ipv6.method -> disabled"
    fi
done < <(nmcli -t -f NAME,DEVICE con show --active)

# Validacao
if [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6)" == "1" ]]; then
    ok "IPv6 desabilitado"
else
    fail "IPv6 continua habilitado"
fi

# =============================================================================
# [2] DESABILITAR FIREWALLD
# =============================================================================
block "[2] Desabilitar firewalld"

if ! systemctl list-unit-files firewalld.service &>/dev/null || \
   ! systemctl list-unit-files | grep -q '^firewalld.service'; then
    ok "firewalld nao esta instalado. Nada a fazer."
else
    fw_active=$(systemctl is-active firewalld 2>/dev/null || true)
    fw_enabled=$(systemctl is-enabled firewalld 2>/dev/null || true)
    info "Estado atual: active=${fw_active} | enabled=${fw_enabled}"

    if [[ "$fw_active" != "active" && "$fw_enabled" == "masked" ]]; then
        ok "firewalld ja esta parado e mascarado. Nada a fazer."
    else
        systemctl stop firewalld    || true
        systemctl disable firewalld || true
        systemctl mask firewalld
        info "firewalld parado, desabilitado e mascarado"
    fi

    # Validacao
    if [[ "$(systemctl is-active firewalld 2>/dev/null || true)" != "active" ]]; then
        ok "firewalld desabilitado"
    else
        fail "firewalld continua ativo"
    fi
fi

# =============================================================================
# [3] DESABILITAR SELINUX
# =============================================================================
#  Obs.: no RHEL/Rocky 9+ a linha SELINUX=disabled no /etc/selinux/config
#  NAO desabilita mais o SELinux por completo. O correto e passar
#  "selinux=0" na linha de boot do kernel (via grubby).
# =============================================================================
block "[3] Desabilitar SELinux"

se_runtime=$(getenforce 2>/dev/null || echo "Disabled")
se_cmdline=$(grubby --info=DEFAULT 2>/dev/null | grep -c 'selinux=0' || true)
info "Estado atual: runtime=${se_runtime} | selinux=0 no kernel: $([[ $se_cmdline -gt 0 ]] && echo sim || echo nao)"

# 3.1 Runtime: Enforcing -> Permissive (efeito imediato, sem reboot)
if [[ "$se_runtime" == "Enforcing" ]]; then
    setenforce 0
    info "SELinux colocado em Permissive (runtime)"
fi

# 3.2 Arquivo de configuracao
if grep -q '^SELINUX=disabled' /etc/selinux/config 2>/dev/null; then
    ok "/etc/selinux/config ja esta com SELINUX=disabled"
else
    backup /etc/selinux/config
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    info "/etc/selinux/config -> SELINUX=disabled"
fi

# 3.3 Kernel cmdline (desabilitacao real)
if [[ $se_cmdline -gt 0 ]]; then
    ok "Parametro selinux=0 ja presente no kernel"
else
    grubby --update-kernel ALL --args selinux=0
    info "Parametro selinux=0 adicionado a todos os kernels"
    REBOOT_REQUIRED=1
fi

# Validacao
if [[ "$(getenforce)" != "Enforcing" ]]; then
    ok "SELinux nao esta em Enforcing (atual: $(getenforce))"
else
    fail "SELinux continua em Enforcing"
fi

# =============================================================================
# [4] ATUALIZAR O SISTEMA
# =============================================================================
block "[4] Atualizar o sistema"

info "Verificando atualizacoes disponiveis..."
set +e
dnf -q check-update >/dev/null
rc=$?
set -e

case $rc in
    0)   ok "Sistema ja esta atualizado" ;;
    100)
        info "Atualizacoes disponiveis. Instalando..."
        dnf -y upgrade --refresh | tee -a "$LOG_FILE"
        ok "Sistema atualizado"
        ;;
    *)   fail "Falha ao consultar repositorios (dnf check-update rc=$rc)" ;;
esac

# Pacotes utilitarios basicos
dnf -y install dnf-plugins-core bind-utils >/dev/null
ok "Utilitarios instalados (dnf-plugins-core, bind-utils)"

# Verifica se precisa reboot (kernel/glibc/systemd atualizados)
if dnf needs-restarting -r &>/dev/null; then
    ok "Nenhum reboot necessario pela atualizacao"
else
    warn "Atualizacao exige reboot"
    REBOOT_REQUIRED=1
fi

# =============================================================================
# [5] DEFINIR DNS (8.8.8.8 / 8.8.4.4 / 1.1.1.1)
# =============================================================================
block "[5] Definir DNS"

info "DNS atual (/etc/resolv.conf):"
grep '^nameserver' /etc/resolv.conf | tee -a "$LOG_FILE" || true

while IFS=: read -r con dev; do
    [[ -z "$dev" || "$dev" == "lo" ]] && continue
    cur_dns=$(nmcli -g ipv4.dns con show "$con" | tr ',' ' ')
    cur_ign=$(nmcli -g ipv4.ignore-auto-dns con show "$con")

    if [[ "$cur_dns" == "$DNS_SERVERS" && "$cur_ign" == "yes" ]]; then
        ok "Conexao '$con' ($dev) ja usa: $DNS_SERVERS"
        continue
    fi

    nmcli con mod "$con" ipv4.dns "$DNS_SERVERS" ipv4.ignore-auto-dns yes
    nmcli con up "$con" >/dev/null
    info "Conexao '$con' ($dev): DNS -> $DNS_SERVERS"
done < <(nmcli -t -f NAME,DEVICE con show --active)

# Validacao
sleep 2
for ns in $DNS_SERVERS; do
    grep -q "^nameserver $ns" /etc/resolv.conf \
        && ok "nameserver $ns presente em /etc/resolv.conf" \
        || warn "nameserver $ns NAO encontrado em /etc/resolv.conf"
done

if dig +short +time=3 +tries=1 rockylinux.org | grep -qE '^[0-9.]+$'; then
    ok "Resolucao DNS funcionando (rockylinux.org)"
else
    fail "Falha na resolucao DNS"
fi

# =============================================================================
# RESUMO
# =============================================================================
block "Resumo"
ok "IPv6 ........ desabilitado"
ok "firewalld ... desabilitado"
ok "SELinux ..... $(getenforce) (disabled apos reboot)"
ok "Sistema ..... atualizado"
ok "DNS ......... $DNS_SERVERS"
info "Log completo: $LOG_FILE"
[[ -d "$BACKUP_DIR" ]] && info "Backups em: $BACKUP_DIR"

if [[ $REBOOT_REQUIRED -eq 1 ]]; then
    echo
    warn "REBOOT NECESSARIO antes de prosseguir com a instalacao do OpenVAS."
    warn "Execute: reboot"
fi
