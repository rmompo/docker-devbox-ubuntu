ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Base tools, Python and build tools. No user and no AI client in the image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget nano git sudo gosu zip unzip less \
        jq openssh-client procps bash-completion gnupg xz-utils ripgrep \
        rsync htop iproute2 bind9-dnsutils make \
        python3 python3-pip python3-venv pipx python-is-python3 \
        build-essential \
        tree iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Enable colors in bash for every user created later (copied from /etc/skel).
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc \
    && printf '%s\n' \
        "alias ls='ls --color=auto'" \
        "alias grep='grep --color=auto'" \
        >> /etc/skel/.bashrc

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
