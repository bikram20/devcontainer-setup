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
  netcat-openbsd \
  curl \
  wget \
  && apt clean \
  && rm -rf /var/lib/apt/lists/*

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
  dpkg -i "git-delta_0.18.2_${ARCH}.deb" && \
  rm "git-delta_0.18.2_${ARCH}.deb"

# Install VS Code CLI for tunneling
RUN curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz && \
    tar -xf vscode_cli.tar.gz && \
    mv code /usr/local/bin/ && \
    rm vscode_cli.tar.gz && \
    chown node:node /usr/local/bin/code

# Create VS Code config directory for tunnel data
RUN mkdir -p /home/node/.vscode-cli && \
    chown -R node:node /home/node/.vscode-cli

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

# Copy application files
COPY --chown=node:node srcs/ /workspace/src/

# Install application dependencies
WORKDIR /workspace/src
RUN npm install

# Create tunnel cleanup script
RUN echo '#!/bin/bash\n\
TUNNEL_NAME="${TUNNEL_NAME:-digitalocean-dev}"\n\
echo "Cleaning up tunnel: $TUNNEL_NAME"\n\
\n\
# Force remove any existing tunnel registration\n\
code tunnel unregister --name "$TUNNEL_NAME" 2>/dev/null || true\n\
\n\
# Clean up local tunnel data\n\
rm -rf /home/node/.vscode-cli/code_tunnel_* 2>/dev/null || true\n\
\n\
# Kill any existing tunnel processes\n\
pkill -f "code.*tunnel" 2>/dev/null || true\n\
\n\
# Wait a moment for cleanup\n\
sleep 2\n\
echo "Tunnel cleanup completed"\n\
' > /home/node/cleanup-tunnel.sh && chmod +x /home/node/cleanup-tunnel.sh

# Create enhanced startup script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Set tunnel name from environment variable with default\n\
export TUNNEL_NAME="${TUNNEL_NAME:-digitalocean-dev}"\n\
\n\
echo "========================================"\n\
echo "🚀 Starting VS Code Tunnel Dev Container"\n\
echo "========================================"\n\
echo "Tunnel name: $TUNNEL_NAME"\n\
echo "App port: ${PORT:-8080}"\n\
echo "========================================"\n\
\n\
# Cleanup any existing tunnel\n\
/home/node/cleanup-tunnel.sh\n\
\n\
# Start the Express app in background\n\
echo "Starting Express application..."\n\
cd /workspace/src\n\
npm start &\n\
APP_PID=$!\n\
\n\
# Trap to ensure cleanup on exit\n\
trap "kill $APP_PID 2>/dev/null || true; /home/node/cleanup-tunnel.sh" EXIT INT TERM\n\
\n\
# Give app time to start\n\
sleep 3\n\
\n\
# Start VS Code tunnel with retry logic\n\
MAX_RETRIES=3\n\
RETRY_COUNT=0\n\
\n\
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do\n\
    echo "Starting VS Code tunnel (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."\n\
    \n\
    if code tunnel --accept-server-license-terms --name "$TUNNEL_NAME" --verbose; then\n\
        echo "VS Code tunnel exited normally"\n\
        break\n\
    else\n\
        EXIT_CODE=$?\n\
        echo "VS Code tunnel failed with exit code: $EXIT_CODE"\n\
        RETRY_COUNT=$((RETRY_COUNT + 1))\n\
        \n\
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then\n\
            echo "Cleaning up and retrying in 10 seconds..."\n\
            /home/node/cleanup-tunnel.sh\n\
            sleep 10\n\
        else\n\
            echo "Max retries reached. Exiting."\n\
            exit $EXIT_CODE\n\
        fi\n\
    fi\n\
done\n\
' > /home/node/start.sh && chmod +x /home/node/start.sh

# Set environment variables
ENV PORT=8080

# Expose port 8080 for the application
EXPOSE 8080

# Start services
CMD ["/home/node/start.sh"]
