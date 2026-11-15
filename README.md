# How to install OpenVAS on Rocky Linux 10.2

Instalação do OpenVAS (Greenbone Community Edition) no Rocky Linux 10.2.

> **Observação:** os scripts deste repositório foram testados **somente no Rocky Linux 10.2**.
> Não garantimos o funcionamento em outras versões do Rocky Linux ou em outras distribuições.

Este repositório contém scripts para instalar o OpenVAS em duas modalidades:

- **VM / bare-metal** — scripts shell executados em blocos, com verificação antes e depois de cada ação.
- **Docker** — instalação via containers (em construção).

## Estrutura

```
install_openvas_rockylinux_10/
├── README.md
├── scripts/
│   ├── 01-prepare-system.sh   # preparação do sistema
│   └── 02-install-openvas.sh  # instalação do OpenVAS/GVM
├── docker/                    # instalação via Docker (em breve)
└── lab/                       # container Rocky Linux 10.2 para testes (ver lab/README.md)
```

## Etapa 01 — Preparação do sistema

```bash
git clone https://github.com/danill6f/install_openvas_rockylinux_10.git
cd install_openvas_rockylinux_10
sudo bash scripts/01-prepare-system.sh
```

| Bloco | Ação |
|---|---|
| [0] | Pré-checagens: root, Rocky Linux 10, `dnf`, `nmcli`, conectividade |
| [1] | Desabilita IPv6 (sysctl + NetworkManager) |
| [2] | Para, desabilita e mascara o `firewalld` |
| [3] | Desabilita o SELinux (runtime, `/etc/selinux/config` e `selinux=0` no kernel) |
| [4] | Atualiza o sistema (`dnf upgrade`) |
| [5] | Define DNS: `8.8.8.8`, `8.8.4.4`, `1.1.1.1` |
| [6] | Verifica se o `wget` está instalado (instala se faltar) |
| [7] | Habilita os repositórios CRB e EPEL |
| [8] | Habilita o repositório Atomicorp (instalador oficial, assumindo "yes") |
| Final | Pergunta se deseja reiniciar o servidor agora (`s/N`) |

Cada bloco segue o fluxo **verifica → aplica (só se necessário) → valida**, então o script pode ser executado mais de uma vez com segurança.

- Log: `/var/log/openvas-install.log`
- Backups de arquivos alterados: `/root/openvas-install-backup/<data>/`

> **Reboot:** no Rocky Linux 9+ o SELinux só é desabilitado por completo após reiniciar com `selinux=0` no kernel. O script avisa ao final quando o reboot for necessário.

## Etapa 02 — Instalação do OpenVAS / GVM

Execute após a etapa 01 **e o reboot**:

```bash
sudo bash scripts/02-install-openvas.sh
```

| Bloco | Ação |
|---|---|
| [0] | Pré-checagens: root, Rocky Linux 10.2, repositório Atomicorp, SELinux fora de Enforcing |
| [1] | Verifica espaço em disco: **mínimo 50 GB livres** em `/var/lib` |
| [2] | Verifica se o `gvm` já está instalado e se o `gvm-setup` já foi executado |
| [3] | `dnf install -y gvm` (somente se não estiver instalado) |
| [4] | `gvm-setup` (somente se ainda não foi executado) |
| [5] | Valida os serviços (`redis`, `gvmd`, `gsad`, `ospd-openvas`) e a porta 9392 |

> O `gvm-setup` baixa os feeds de vulnerabilidades e pode levar de 30 minutos a algumas horas. Não interrompa.

Ao final, acesse: `https://<ip-do-servidor>:9392`

## Aviso

Desabilitar firewall, SELinux e IPv6 reduz a proteção do servidor. Use em ambiente de laboratório ou em uma rede protegida.
