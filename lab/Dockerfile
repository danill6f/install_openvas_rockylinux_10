# Laboratorio Rocky Linux 10.2 com systemd
# Usado para escrever e testar o manual de instalacao do OpenVAS.
FROM rockylinux/rockylinux:10.2

RUN dnf -y install \
        systemd procps-ng iproute iputils hostname which \
        sudo vim-minimal less tar git wget bind-utils \
    && dnf clean all \
    && rm -f /etc/systemd/system/*.wants/* \
             /lib/systemd/system/multi-user.target.wants/* \
             /lib/systemd/system/local-fs.target.wants/* \
             /lib/systemd/system/sockets.target.wants/*udev* \
             /lib/systemd/system/sockets.target.wants/*initctl* \
             /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
    && systemctl set-default multi-user.target

WORKDIR /opt/install_openvas_rockylinux_10

STOPSIGNAL SIGRTMIN+3
CMD ["/usr/sbin/init"]
