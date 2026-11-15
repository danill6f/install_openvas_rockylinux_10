# Laboratório Rocky Linux 10.2 (Docker)

Container Rocky Linux 10.2 com systemd, usado para escrever e testar o manual.

## Subir

```bash
cd install_openvas_rockylinux_10/lab
docker compose up -d --build
docker exec -it rocky10-lab bash
```

Dentro do container, o repositório fica em `/opt/install_openvas_rockylinux_10`.

```bash
cat /etc/rocky-release      # confirma a versao 10.2
systemctl is-system-running # systemd ativo
```

## Parar / remover

```bash
docker compose down         # para e remove o container
docker compose down --rmi local  # remove tambem a imagem
```

## Limitações do container

Um container compartilha o kernel do host. Por isso, alguns blocos do
`scripts/01-prepare-system.sh` **não se aplicam** aqui e devem ser validados em uma **VM Rocky Linux 10.2**:

| Bloco | No container |
|---|---|
| [1] IPv6 | Afeta só a rede do container |
| [2] firewalld | Não vem instalado |
| [3] SELinux | Controlado pelo host; `grubby` não existe |
| [5] DNS | Sem NetworkManager; DNS é definido pelo Docker |
| Reboot | Não se aplica (use `docker restart rocky10-lab`) |

Os blocos de pacotes e repositórios (**[4] update, [6] wget, [7] CRB/EPEL, [8] Atomicorp**) funcionam normalmente.
