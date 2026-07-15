FROM docker/sandbox-templates:codex-docker

USER root

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

COPY files/home/.local/share/vscode-in-sandbox/install-tools.sh /tmp/vscode-in-sandbox/install-tools.sh

RUN bash /tmp/vscode-in-sandbox/install-tools.sh \
  && rm -rf /tmp/vscode-in-sandbox

COPY files/etc/ssh/sshd_config.d/vscode-in-sandbox.conf /etc/ssh/sshd_config.d/vscode-in-sandbox.conf

# Public-key login works while password authentication remains disabled in sshd.
RUN passwd -d agent

COPY --chown=agent:agent files/home/.config/vscode-in-sandbox/extensions.txt /home/agent/.config/vscode-in-sandbox/extensions.txt
COPY --chown=agent:agent files/home/.vscode-server/data/Machine/settings.json /home/agent/.vscode-server/data/Machine/settings.json
COPY --chown=agent:agent files/home/.zshrc /home/agent/.zshrc
COPY --chown=agent:agent files/home/.local/share/vscode-in-sandbox/install-extensions.sh /tmp/vscode-in-sandbox/install-extensions.sh

USER agent

RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /home/agent/.oh-my-zsh

RUN code --version

RUN bash /tmp/vscode-in-sandbox/install-extensions.sh \
  && rm -rf /tmp/vscode-in-sandbox

USER agent
