FROM node:20

ARG TZ
ENV TZ="$TZ"

# Install basic development tools
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
  netcat-openbsd

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set DEVCONTAINER environment variable
ENV DEVCONTAINER=true

# Create workspace directory
RUN mkdir -p /workspace && \
  chown -R node:node /workspace

WORKDIR /workspace

# Install delta for better git diffs
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_0.18.2_${ARCH}.deb" && \
  rm "git-delta_0.18.2_${ARCH}.deb"

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

# Set the default shell to zsh
ENV SHELL=/bin/zsh

# Install zsh with plugins
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.2.0/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Claude
RUN npm install -g @anthropic-ai/claude-code

# Create a simple health check server script
RUN echo '#!/bin/bash\n\
while true; do\n\
  echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | nc -l -p 8080 -q 1\n\
done\n\
' > /home/node/health-server.sh && chmod +x /home/node/health-server.sh

# Create simplified startup script with cleanup
RUN echo '#!/bin/bash\n\
echo "========================================"\n\
echo "🚀 Starting VS Code Tunnel Dev Container"\n\
echo "========================================"\n\
echo "Tunnel name: ${TUNNEL_NAME:-digitalocean-dev}"\n\
\n\
# Clean up any existing tunnel registration\n\
echo "Cleaning up any existing tunnel..."\n\
code tunnel unregister --name "${TUNNEL_NAME:-digitalocean-dev}" 2>/dev/null || true\n\
\n\
echo "Starting health check server on port 8080..."\n\
# Start health check server in background for DigitalOcean\n\
/home/node/health-server.sh &\n\
\n\
echo "Starting VS Code tunnel..."\n\
# Start the tunnel with verbose output\n\
code tunnel --accept-server-license-terms --name "${TUNNEL_NAME:-digitalocean-dev}" --verbose\n\
' > /home/node/start.sh && chmod +x /home/node/start.sh

# Expose port 8080 for health checks
EXPOSE 8080

# Start services
CMD ["/home/node/start.sh"]