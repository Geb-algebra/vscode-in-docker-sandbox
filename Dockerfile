FROM docker/sandbox-templates:codex-docker

USER root

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
ENV PLAYWRIGHT_MCP_BROWSER=chromium

COPY files/home/.local/share/vscode-in-sandbox /home/agent/.local/share/vscode-in-sandbox
COPY artifacts /home/agent/.local/share/vscode-in-sandbox/artifacts

RUN printf '%s\n' /home/agent/.local/share/vscode-in-sandbox/artifacts \
      > /home/agent/.local/share/vscode-in-sandbox/artifact-path \
  && bash /home/agent/.local/share/vscode-in-sandbox/install-tools.sh \
  && rm -rf /home/agent/.local/share/vscode-in-sandbox/artifacts

COPY --chown=agent:agent files/home/.config/vscode-in-sandbox/extensions.txt /home/agent/.config/vscode-in-sandbox/extensions.txt
COPY --chown=agent:agent files/home/.vscode-server/data/Machine/settings.json /home/agent/.vscode-server/data/Machine/settings.json
COPY --chown=agent:agent files/home/.zshrc /home/agent/.zshrc
USER agent
