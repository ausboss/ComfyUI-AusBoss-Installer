# AusBoss nodes on RunPod

On RunPod you don't need the installer. There are two ways to get ComfyUI with the AusBoss nodes on a pod:

- **The AusBoss image** (below) has ComfyUI, PyTorch, ComfyUI-Manager and both AusBoss packs built in. Nothing installs when the pod starts, and the ComfyUI page asks for a token, so a leaked link doesn't give away your GPU. AI agents can queue work on it too.
- **RunPod's official ComfyUI template** ([further down](#runpods-official-template)) is a minute to start, and you add the AusBoss packs from the Manager.

The installer builds everything from scratch, which is what you want on your own PC. On a pod that takes 15 minutes or more, because the pod's `/workspace` is network storage and PyTorch is thousands of files.

## The AusBoss image

The image is `ghcr.io/ausboss/comfyui-ausboss`, in two builds:

| Tag | For |
|---|---|
| `cuda12.8` | Every GPU before Blackwell: RTX 3090, 4090, A5000, A40, L40S, A100, H100 |
| `cuda13.0` | Blackwell: RTX 5090, RTX PRO 6000, B200 |

Pin a version (`0.1.0-cuda12.8`) if you want a pod to keep the same ComfyUI and node versions until you change it.

### Make a template

Do this once; every pod after that is two clicks.

1. In the RunPod console open **Secrets**, click **Create Secret**, name it `comfyui_token` and paste a long random value (for example the output of `openssl rand -base64 24`). That is your password for ComfyUI.
2. Open **My Templates → New Template** and fill in:
   - **Container image:** `ghcr.io/ausboss/comfyui-ausboss:cuda12.8` (or `:cuda13.0` for Blackwell; make one template for each).
   - **Container disk:** 30 GB. The image is about 18 GB unpacked.
   - **Volume disk:** 50 GB or more, mounted at `/workspace`. Your models live here.
   - **HTTP ports:** `8188`. **TCP ports:** `22` if you want SSH.
   - **Environment variables:** `COMFYUI_TOKEN` = `{{ RUNPOD_SECRET_comfyui_token }}`.
3. Save it.

### Start a pod

1. **Pods → Deploy**, pick a GPU, **Change Template**, and pick yours. Use the `cuda13.0` template for a Blackwell card.
2. **Deploy On-Demand.** The first start on a host downloads the image, which takes a few minutes. ComfyUI then starts right away, with nothing to install.
3. **Connect → HTTP Service → :8188**, paste your token, and you're in. The browser remembers it for 30 days.

If you deploy without `COMFYUI_TOKEN`, the pod makes a token, prints it in the pod's logs and saves it in `/workspace/ausboss/.comfyui_token`.

### What's where

Everything you'd want to keep is on the volume, in `/workspace/ausboss`:

| Path | What |
|---|---|
| `models/` | Model files, in the usual ComfyUI folders |
| `output/`, `input/` | What you make and what you upload |
| `user/` | Settings, saved workflows, ComfyUI-Manager's settings |
| `custom_nodes/` | Node packs you add from the Manager |
| `venv/` | Python packages those packs need |
| `comfyui_args.txt` | Extra ComfyUI options, one per line; restart the pod to apply |

ComfyUI itself, PyTorch, ComfyUI-Manager and the built-in packs (ComfyUI-AusBoss, AusBoss Model Downloader, and RunPod's KJNodes, Civicomfy and RunpodDirect) are part of the image. To update them, deploy a newer image tag. Clicking **Update** on them in the Manager only lasts until the pod restarts.

Packs you install from the Manager go to `/workspace/ausboss/custom_nodes` and stay. Their Python packages go into `/workspace/ausboss/venv`, which sits on top of the image's packages, so PyTorch is never reinstalled.

### Let an agent use it

The pod's ComfyUI takes jobs over HTTP with the same token, sent as `Authorization: Bearer <token>`. The [comfyui-pod skill](../skills/comfyui-pod/SKILL.md) gives an AI agent (Claude Code, Codex and the like) a small command-line tool for it: queue a workflow with changed prompts or settings, queue batches, wait, download the results, list models. Copy the `skills/comfyui-pod` folder into your agent's skills folder, then tell it the pod's address and token.

Jobs from the agent and from you in the browser go into the same queue, so you can watch the agent's work in the ComfyUI page as it runs.

### Good to know

- **Only port 8188 is open,** and it checks the token on every request. ComfyUI itself listens on the pod's loopback address. The image doesn't start JupyterLab or FileBrowser, which have their own logins; SSH takes keys only (RunPod adds yours from **Settings → SSH Public Keys**).
- **Sign out** with `/__logout` on the pod's address.
- **Change the token** by editing the secret and restarting the pod. Signed-in browsers have to sign in again.

## RunPod's official template

RunPod's official ComfyUI template already has ComfyUI, PyTorch and ComfyUI-Manager built in, so a pod is up in about a minute, and the AusBoss packs install on top of it from the Manager in a couple more.

### 1. Start a pod

1. In the RunPod console, open **Pods** and click **Deploy**.
2. Pick a GPU. 24 GB (RTX 4090, RTX 3090, A5000) is enough for images and most video workflows; take 48 GB or more (A40, L40S, RTX 6000 Ada) for the bigger video models.
3. Click **Change Template** and pick the one that matches the GPU:
   - [**ComfyUI - CUDA 12.8**](https://console.runpod.io/hub/template/cw3nka7d08) for everything before Blackwell (RTX 4090, 3090, A40, L40S, A100, H100).
   - [**ComfyUI - CUDA 13**](https://console.runpod.io/hub/template/2lv7ev3wfp) for Blackwell (RTX 5090, RTX PRO 6000, B200).
4. Click **Deploy On-Demand**.

### 2. Open ComfyUI

When the pod shows **Running**, click **Connect**, then **HTTP Service → :8188**. If you get a 502 page, ComfyUI is still starting; reload in a few seconds.

### 3. Install the AusBoss nodes

1. Click **Manager** in the top bar, then **Custom Nodes Manager**.
2. Search for **AusBoss**.
3. Click **Install** on **ComfyUI-AusBoss** and on **AusBoss Model Downloader**.
4. Click **Restart** when the Manager asks, then reload the page.

Double-click the canvas and search for **AusBoss** to check the nodes are there.

### 4. Get models

Add a **Model Downloader 🆎** node, paste a Civitai or Hugging Face link and click **Download**; it saves the file into the right folder on the pod. Workflows with a **Workflow Note** show a download button on each model row, so opening an AusBoss workflow and clicking down the list gets everything it needs.

Downloads run on the pod at datacenter speed, not through your browser.

### 5. When you're done

- **Stop** the pod to pause it. You stop paying for the GPU but keep paying a little for its disk, and your models and nodes are still there next time.
- **Terminate** the pod to delete it and everything on it. Download the outputs you want to keep first. They're in `/workspace/runpod-slim/ComfyUI/output`, and the template's file browser (**Connect → :8080**) can download them.

### Good to know

- **The ComfyUI link has no password.** Anyone with the `…proxy.runpod.net` address can use your pod and your GPU time. Don't post it.
- **Picking the wrong template for the GPU** is the most common first-run failure. A Blackwell card needs the CUDA 13 template.
- **ComfyUI lives in `/workspace/runpod-slim/ComfyUI`**, custom nodes in `custom_nodes` under it. Extra startup options go in `/workspace/runpod-slim/comfyui_args.txt`, one per line.
- **The template can ship an older ComfyUI.** If a node complains about the ComfyUI version, click **Manager → Update ComfyUI**, then restart.
