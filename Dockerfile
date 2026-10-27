FROM docker/sandbox-templates:codex-docker

USER root

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
ENV PLAYWRIGHT_MCP_BROWSER=chromium

COPY files/home/.local/share/vscode-in-sandbox/mise-config.toml /home/agent/.local/share/vscode-in-sandbox/mise-config.toml
COPY files/home/.local/share/vscode-in-sandbox/install-tools.sh /tmp/vscode-in-sandbox/install-tools.sh

RUN bash /tmp/vscode-in-sandbox/install-tools.sh \
  && rm -rf /tmp/vscode-in-sandbox

COPY --chown=agent:agent files/home/.vscode-server/data/Machine/settings.json /home/agent/.vscode-server/data/Machine/settings.json
COPY --chown=agent:agent files/home/.zshrc /home/agent/.zshrc
USER agent

ENV IS_SANDBOX=1
ENV BROWSER=xdg-open
ENV CODEX_HOME=/home/agent/.codex
ENV GIT_TERMINAL_PROMPT=0
