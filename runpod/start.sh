#!/bin/bash
# Boots the AusBoss ComfyUI image. ComfyUI, PyTorch and the baked node packs
# run straight from the image; only user data lives on /workspace:
#   /workspace/ausboss/models, input, output, user, custom_nodes (packs you add)
#   /workspace/ausboss/venv              Python packages those packs add
#   /workspace/ausboss/comfyui_args.txt  extra ComfyUI options, one per line
set -uo pipefail

COMFY=/opt/comfyui-baked
DATA="${AUSBOSS_DATA:-/workspace/ausboss}"
VENV="$DATA/venv"
ARGS_FILE="$DATA/comfyui_args.txt"
COMFY_PORT=8189

mkdir -p "$DATA"/{custom_nodes,input,output,user,models}

# Empty model folders so the loaders list them; never touches existing files.
(cd "$COMFY/models" && find . -type d -exec mkdir -p "$DATA/models/{}" \;)
[ -d "$DATA/user/__manager" ] || cp -a "$COMFY/user/__manager" "$DATA/user/" 2>/dev/null || true
[ -f "$ARGS_FILE" ] || echo "# Extra ComfyUI options, one per line, for example --preview-method auto" > "$ARGS_FILE"

# ---- access token -----------------------------------------------------------
if [ -z "${COMFYUI_TOKEN:-}" ]; then
    TOKEN_FILE="$DATA/.comfyui_token"
    if [ ! -s "$TOKEN_FILE" ]; then
        (umask 077; python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > "$TOKEN_FILE")
    fi
    COMFYUI_TOKEN="$(cat "$TOKEN_FILE")"
    echo "COMFYUI_TOKEN is not set, so this pod made one and saved it in $TOKEN_FILE:"
    echo "    $COMFYUI_TOKEN"
fi
export COMFYUI_TOKEN

# ---- Python -----------------------------------------------------------------
# Everything ComfyUI needs is installed in the image. This venv sees those
# packages and holds only what packs you add install, so it stays small and
# survives restarts. pip comes from the image, so the venv is made without one.
if [ ! -x "$VENV/bin/python" ]; then
    echo "Creating $VENV"
    python3.12 -m venv --system-site-packages --without-pip "$VENV"
fi
export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt
export PATH="$VENV/bin:$PATH" VIRTUAL_ENV="$VENV"
echo "export PATH=\"$VENV/bin:\$PATH\" VIRTUAL_ENV=\"$VENV\" PIP_CONSTRAINT=\"$PIP_CONSTRAINT\"" > /etc/profile.d/ausboss.sh

# Packs added on an earlier boot: install their requirements again if the
# venv was recreated or the file changed. pip skips what is already there.
for req in "$DATA"/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue
    pack="$(basename "$(dirname "$req")")"
    stamp="$VENV/.requirements-$pack"
    if [ ! -f "$stamp" ] || [ "$req" -nt "$stamp" ]; then
        echo "Installing requirements for $pack"
        python -m pip install -q -r "$req" && touch "$stamp"
    fi
done

# ---- SSH (key only) ---------------------------------------------------------
if [ -n "${PUBLIC_KEY:-}" ]; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    grep -qxF "$PUBLIC_KEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    [ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A -q
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/; s/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    mkdir -p /run/sshd && /usr/sbin/sshd
fi

# ---- run --------------------------------------------------------------------
STOPPING=0
COMFY_PID=""
stop() {
    STOPPING=1
    kill "$COMFY_PID" "$PROXY_PID" 2>/dev/null
}
trap stop SIGTERM SIGINT

python3 /opt/ausboss/auth_proxy.py &
PROXY_PID=$!

cd "$COMFY" || exit 1
while [ "$STOPPING" = 0 ]; do
    mapfile -t EXTRA < <(grep -v '^[[:space:]]*#' "$ARGS_FILE" | xargs -r -n1 2>/dev/null)
    echo "Starting ComfyUI ${EXTRA[*]}"
    python main.py --listen 127.0.0.1 --port "$COMFY_PORT" \
        --base-directory "$DATA" --temp-directory /tmp \
        --extra-model-paths-config /opt/ausboss/extra_model_paths.yaml \
        "${EXTRA[@]}" &
    COMFY_PID=$!
    wait "$COMFY_PID"
    code=$?
    [ "$STOPPING" = 1 ] && break
    echo "ComfyUI exited with code $code; starting it again in 5 seconds."
    sleep 5
done
wait "$PROXY_PID" 2>/dev/null
