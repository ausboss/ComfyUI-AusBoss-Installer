# AusBoss nodes on RunPod

On RunPod you don't need the installer. RunPod's official ComfyUI template already has ComfyUI, PyTorch and ComfyUI-Manager built in, so a pod is up in about a minute, and the AusBoss packs install on top of it from the Manager in a couple more.

The installer builds everything from scratch, which is what you want on your own PC. On a pod that takes 15 minutes or more, because the pod's `/workspace` is network storage and PyTorch is thousands of files.

## 1. Start a pod

1. In the RunPod console, open **Pods** and click **Deploy**.
2. Pick a GPU. 24 GB (RTX 4090, RTX 3090, A5000) is enough for images and most video workflows; take 48 GB or more (A40, L40S, RTX 6000 Ada) for the bigger video models.
3. Click **Change Template** and pick the one that matches the GPU:
   - [**ComfyUI - CUDA 12.8**](https://console.runpod.io/hub/template/cw3nka7d08) for everything before Blackwell (RTX 4090, 3090, A40, L40S, A100, H100).
   - [**ComfyUI - CUDA 13**](https://console.runpod.io/hub/template/2lv7ev3wfp) for Blackwell (RTX 5090, RTX PRO 6000, B200).
4. Click **Deploy On-Demand**.

## 2. Open ComfyUI

When the pod shows **Running**, click **Connect**, then **HTTP Service → :8188**. If you get a 502 page, ComfyUI is still starting; reload in a few seconds.

## 3. Install the AusBoss nodes

1. Click **Manager** in the top bar, then **Custom Nodes Manager**.
2. Search for **AusBoss**. You should see two rows, **AusBoss** and **AusBoss Model Downloader**. If only one shows up, the Manager is still loading the Registry a few minutes after the pod started: close the window, wait a minute and open it again.
3. Click **Install** on **AusBoss**. Leave **latest** selected and click **Select**.
4. Click **Install** on **AusBoss Model Downloader**, pick **0.2.1** in the list and click **Select**. Don't take **nightly** here: on a pod the Manager only allows numbered versions of this pack and stops with a "security level" error.
5. Click **Restart** at the bottom of the window and **Confirm**. Wait for ComfyUI to come back, then reload the page.

Double-click the canvas and search for **AusBoss** to check the nodes are there.

## 4. Get models

Add a **Model Downloader 🆎** node, paste a Civitai or Hugging Face link and click **Download**; it saves the file into the right folder on the pod. Workflows with a **Workflow Note** show a download button on each model row, so opening an AusBoss workflow and clicking down the list gets everything it needs.

Downloads run on the pod at datacenter speed, not through your browser.

## 5. When you're done

- **Stop** the pod to pause it. You stop paying for the GPU but keep paying a little for its disk, and your models and nodes are still there next time.
- **Terminate** the pod to delete it and everything on it. Download the outputs you want to keep first. They're in `/workspace/runpod-slim/ComfyUI/output`, and the template's file browser (**Connect → :8080**) can download them.

## Good to know

- **The ComfyUI link has no password.** Anyone with the `…proxy.runpod.net` address can use your pod and your GPU time. Don't post it.
- **Picking the wrong template for the GPU** is the most common first-run failure. A Blackwell card needs the CUDA 13 template.
- **ComfyUI lives in `/workspace/runpod-slim/ComfyUI`**, custom nodes in `custom_nodes` under it. Extra startup options go in `/workspace/runpod-slim/comfyui_args.txt`, one per line.
- **The template can ship an older ComfyUI.** If a node complains about the ComfyUI version, click **Manager → Update ComfyUI**, then restart.
