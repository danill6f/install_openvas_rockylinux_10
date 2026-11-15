# install_openvas_rockylinux_10

How to install OpenVAS (Greenbone Community Edition) on Rocky Linux 10.

Este repositório contém scripts para instalar o OpenVAS em duas modalidades:

- **VM / bare-metal** — scripts shell executados em blocos, com verificação antes e depois de cada ação.
- **Docker** — instalação via containers (em construção).

## Estrutura

```
install_openvas_rockylinux_10/
├── README.md
├── scripts/
│   └── 01-prepare-system.sh   # preparação do sistema
└── docker/                    # instalação via Docker (em breve)
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

Cada bloco segue o fluxo **verifica → aplica (só se necessário) → valida**, então o script pode ser executado mais de uma vez com segurança.

- Log: `/var/log/openvas-install.log`
- Backups de arquivos alterados: `/root/openvas-install-backup/<data>/`

> **Reboot:** no Rocky Linux 9+ o SELinux só é desabilitado por completo após reiniciar com `selinux=0` no kernel. O script avisa ao final quando o reboot for necessário.

## Aviso

Desabilitar firewall, SELinux e IPv6 reduz a proteção do servidor. Use em ambiente de laboratório ou em uma rede protegida.
