---
name: comfyui-pod
description: Generate images and video on a ComfyUI server (an AusBoss RunPod pod or any ComfyUI) by queueing API-format workflows with changed inputs, running batches, waiting for results and downloading the files. Use when someone asks you to generate, render or batch something "on the pod" or "in ComfyUI", or to list the models a ComfyUI server has.
license: MIT
compatibility: Python 3.8+ with no extra packages. Needs the server address and its access token in COMFYUI_URL and COMFYUI_TOKEN.
metadata:
  author: AusBoss
  homepage: https://github.com/ausboss/ComfyUI-AusBoss-Installer/blob/main/docs/runpod.md
---

# ComfyUI pod

`comfyui_pod.py` (next to this file) talks to ComfyUI's HTTP API. Every command
prints JSON, errors go to stderr as `{"error": ...}` with exit code 2, and a job that
fails exits 1.

## Setup

The person gives you two things. Put them in the environment, never in a file you
commit or in your reply:

```bash
export COMFYUI_URL=https://<pod-id>-8188.proxy.runpod.net   # RunPod: Connect > HTTP Service > :8188
export COMFYUI_TOKEN=...                                     # the COMFYUI_TOKEN set when the pod was deployed
python3 comfyui_pod.py status
```

`status` shows the ComfyUI version, GPU memory and how many jobs are queued. "The pod
rejected the token" means the token is wrong; "ComfyUI is not up yet" means the pod is
still booting, so wait 10 seconds and try again.

## Workflows

ComfyUI runs workflows in **API format**: a JSON object of node id to
`{class_type, inputs}`. The person makes one in the ComfyUI page with **Workflow > Export
(API)**. The normal save file (with `nodes` and `links`) is refused with that hint.

Look before you change anything:

```bash
python3 comfyui_pod.py inspect workflow_api.json
```

This lists each node's id, class, title and the inputs you can set (links to other
nodes are left out). Then change inputs with `--set NODE.INPUT=VALUE`:

- `NODE` is a node id (`6`), its title (`Positive Prompt`), or a class that appears once (`KSampler`).
- `VALUE` is read as JSON when it parses (`20`, `7.5`, `true`) and as text otherwise. `@file.txt` reads the text from a file, which is the safe way to pass a long prompt.

## Run something

```bash
# one job, wait for it, save the outputs
python3 comfyui_pod.py queue wf.json --set "Positive Prompt.text=a red fox in snow"     --set KSampler.steps=25 --random-seed --download ./out

# four variations of the same settings
python3 comfyui_pod.py queue wf.json --count 4 --random-seed --download ./out

# a batch: one JSON object of overrides per line
cat > jobs.jsonl <<'EOF'
{"Positive Prompt.text": "a red fox in snow", "EmptyLatentImage.width": 1216}
{"Positive Prompt.text": "a lighthouse at dusk", "EmptyLatentImage.width": 832}
EOF
python3 comfyui_pod.py queue wf.json --batch jobs.jsonl --random-seed     # returns at once
python3 comfyui_pod.py wait <prompt_id> <prompt_id> --download ./out      # later
```

`queue` without `--wait` or `--download` returns as soon as the jobs are accepted and
prints their `prompt_id`s. Use that for anything long (video takes minutes), and come
back with `wait` or `download`. `--set` values apply to every job; a batch line wins
over them. `--dry-run` prints what would be queued.

Without `--random-seed`, identical jobs give identical results: ComfyUI caches them and
hands back the same file.

A rejected workflow prints ComfyUI's `node_errors`. The usual causes are a model file
name the server doesn't have, or a value outside the input's range. Check them with:

```bash
python3 comfyui_pod.py models                  # model folders
python3 comfyui_pod.py models checkpoints      # files in one folder (loras, vae, diffusion_models, ...)
python3 comfyui_pod.py nodes KSampler          # one node's inputs, types and allowed values
python3 comfyui_pod.py nodes --search ausboss  # find installed nodes
```

## Input files

```bash
python3 comfyui_pod.py upload photo.png        # prints "use_as": the name to put in LoadImage.image
python3 comfyui_pod.py queue wf.json --set LoadImage.image=photo.png --download ./out
```

## Sharing the pod with a person

The person may be using the same ComfyUI in their browser. Jobs from both of you go in
one queue and run in order.

- Check `status` before a big batch. If the queue is already long, say so and ask.
- `list` shows the queue; `mine` is true only for jobs this process queued.
- `cancel <prompt_id>` removes a waiting job or stops a running one. Only cancel jobs you
  queued, unless the person asks.
- `--front` jumps the queue. Don't use it unless asked.
- The pod costs money by the hour. Tell the person when you're done so they can stop it.

## Other commands

`history --limit N` lists recent finished jobs with their files, `download <prompt_id>... -o DIR`
saves outputs of finished jobs (files already in DIR are skipped), and every command
takes `--help`.
