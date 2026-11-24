# AusBoss ComfyUI image for RunPod (and any Docker host with an NVIDIA GPU).
# Built on RunPod's own ComfyUI image, which pins PyTorch per CUDA version and
# installs every dependency system-wide. This adds the AusBoss packs, a token
# gate in front of ComfyUI, and a start script that runs ComfyUI from the image
# instead of copying it to /workspace.
#
#   docker build -f runpod/Dockerfile --build-arg CUDA=cuda13.0 -t comfyui-ausboss:cuda13.0 .
ARG RUNPOD_BASE=2.4.1-comfyuiv0.44.0
ARG CUDA=cuda12.8
FROM runpod/comfyui:${RUNPOD_BASE}-${CUDA}

LABEL org.opencontainers.image.source=https://github.com/ausboss/ComfyUI-AusBoss-Installer \
      org.opencontainers.image.description="ComfyUI with PyTorch, ComfyUI-Manager and the AusBoss node packs, behind an access token" \
      org.opencontainers.image.licenses=MIT

COPY nodes.txt /opt/ausboss/nodes.txt
RUN set -eu; cd /opt/comfyui-baked/custom_nodes; \
    grep -vE '^[[:space:]]*(#|$)' /opt/ausboss/nodes.txt | while read -r url name _; do \
        name="${name:-$(basename "$url" .git)}"; \
        git clone -q --recursive "$url" "$name"; \
        if [ -s "$name/requirements.txt" ]; then \
            PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt pip install --no-cache-dir -q -r "$name/requirements.txt"; \
        fi; \
        echo "$name $(git -C "$name" describe --tags --always) $(git -C "$name" rev-parse HEAD)" >> /opt/ausboss/versions.txt; \
    done; \
    PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt pip install --no-cache-dir -q pymatting pillow-jxl-plugin; \
    cat /opt/comfyui-baked/.runpod-bundle-version >> /opt/ausboss/versions.txt

COPY runpod/start.sh runpod/auth_proxy.py runpod/extra_model_paths.yaml /opt/ausboss/

ENV COMFYUI_TOKEN=""
EXPOSE 8188 22
WORKDIR /workspace
ENTRYPOINT ["/opt/ausboss/start.sh"]
