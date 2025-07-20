FROM node:20

ARG TZ
ENV TZ="$TZ"

# Install basic development tools and iptables/ipset
RUN apt update && apt install -y less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  openssl \
  netcat-openbsd

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_0.18.2_${ARCH}.deb" && \
  rm "git-delta_0.18.2_${ARCH}.deb"

# Install code-server (as root before switching users)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install VS Code CLI for tunneling
RUN curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz && \
    tar -xf vscode_cli.tar.gz && \
    mv code /usr/local/bin/ && \
    rm vscode_cli.tar.gz && \
    chown node:node /usr/local/bin/code

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Default powerline10k theme
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.2.0/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Claude
RUN npm install -g @anthropic-ai/claude-code

# Create code-server config directory
RUN mkdir -p /home/node/.config/code-server

# Create a simple health check server script
RUN echo '#!/bin/bash\n\
while true; do\n\
  echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | nc -l -p 8080 -q 1\n\
done\n\
' > /home/node/health-server.sh && chmod +x /home/node/health-server.sh

# Create startup script with token generation
RUN echo '#!/bin/bash\n\
# Generate random token if not provided\n\
if [ -z "$AUTH_TOKEN" ]; then\n\
    AUTH_TOKEN=$(openssl rand -hex 24)\n\
fi\n\
\n\
# Create code-server config with authentication\n\
cat > /home/node/.config/code-server/config.yaml << EOF\n\
bind-addr: 0.0.0.0:8080\n\
auth: password\n\
password: ${AUTH_TOKEN}\n\
cert: false\n\
EOF\n\
\n\
# Display access information\n\
echo "========================================"\n\
echo "🔐 CODE-SERVER ACCESS INFORMATION:"\n\
echo "========================================"\n\
if [ "$USE_TUNNEL" = "true" ]; then\n\
    echo "Starting VS Code tunnel..."\n\
    echo "Tunnel name: ${TUNNEL_NAME:-digitalocean-dev}"\n\
    # Start health check server in background for DigitalOcean\n\
    /home/node/health-server.sh &\n\
    # Start the tunnel\n\
    code tunnel --accept-server-license-terms --name "${TUNNEL_NAME:-digitalocean-dev}"\n\
else\n\
    echo "URL: https://${APP_URL:-your-app.ondigitalocean.app}"\n\
    echo "Password: ${AUTH_TOKEN}"\n\
    echo ""\n\
    echo "Or use this direct link:"\n\
    echo "https://${APP_URL:-your-app.ondigitalocean.app}?password=${AUTH_TOKEN}"\n\
    echo "========================================"\n\
    exec code-server /workspace\n\
fi\n\
' > /home/node/start.sh && chmod +x /home/node/start.sh

# Ensure proper ownership
RUN chown -R node:node /home/node/.config

# Expose port 8080 for code-server OR health checks
EXPOSE 8080

# Start services
CMD ["/home/node/start.sh"]