#!/usr/bin/env python3
"""Drive a ComfyUI server (an AusBoss RunPod pod, or any ComfyUI) from the command line.

Every command prints JSON. Set COMFYUI_URL and COMFYUI_TOKEN, or pass --url and --token.
Run with --help, or <command> --help, for the options.
"""

import argparse
import getpass
import json
import os
import random
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

CLIENT_ID = os.environ.get("COMFYUI_CLIENT_ID") or str(uuid.uuid5(uuid.NAMESPACE_DNS, "comfyui-pod-%s-%s" % (socket.gethostname(), os.getuid() if hasattr(os, "getuid") else getpass.getuser())))
SEED_INPUTS = ("seed", "noise_seed")


class ComfyError(Exception):
    pass


class Client:
    def __init__(self, url, token):
        if not url:
            raise ComfyError("Set COMFYUI_URL (for example https://<pod-id>-8188.proxy.runpod.net) or pass --url.")
        self.url = url.rstrip("/")
        self.token = token

    def request(self, method, path, body=None, headers=None, raw=False, timeout=60):
        # RunPod's proxy (Cloudflare) answers 403 to urllib's default User-Agent.
        headers = {"User-Agent": "comfyui-pod/1.0", **(headers or {})}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.url + path, data=body, method=method, headers=headers)
        try:
            resp = urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            if e.code == 401:
                raise ComfyError("The pod rejected the token. Check COMFYUI_TOKEN.")
            if e.code in (502, 503):
                raise ComfyError("ComfyUI is not up yet (HTTP %d). Wait a few seconds and try again." % e.code)
            try:
                detail = json.loads(detail)
            except ValueError:
                pass
            raise ComfyError({"http_status": e.code, "error": detail})
        except urllib.error.URLError as e:
            raise ComfyError("Could not reach %s: %s" % (self.url, e.reason))
        if raw:
            return resp
        with resp:
            data = resp.read()
        return json.loads(data) if data else None

    def get(self, path, **kw):
        return self.request("GET", path, **kw)

    def post(self, path, body=None, **kw):
        return self.request("POST", path, body, **kw)


def out(obj):
    print(json.dumps(obj, indent=None if isinstance(obj, dict) and len(json.dumps(obj)) < 200 else 2))


# --------------------------------------------------------------- workflows --

def load_workflow(path):
    with open(path, encoding="utf-8") as f:
        wf = json.load(f)
    if isinstance(wf, dict) and "prompt" in wf and isinstance(wf["prompt"], dict):
        wf = wf["prompt"]
    if isinstance(wf, dict) and "nodes" in wf and "links" in wf:
        raise ComfyError(path + " is a UI workflow. In ComfyUI open it and use Workflow > Export (API), then use that file.")
    if not isinstance(wf, dict) or not all(isinstance(n, dict) and "class_type" in n for n in wf.values()):
        raise ComfyError(path + " is not an API-format workflow (a JSON object of node id -> {class_type, inputs}).")
    return wf


def find_node(wf, ref):
    if ref in wf:
        return ref
    by_title = [k for k, n in wf.items() if n.get("_meta", {}).get("title") == ref]
    if len(by_title) == 1:
        return by_title[0]
    by_class = [k for k, n in wf.items() if n.get("class_type") == ref]
    if len(by_class) == 1:
        return by_class[0]
    matches = by_title or by_class
    if matches:
        raise ComfyError("'%s' matches nodes %s; use the node id instead." % (ref, ", ".join(matches)))
    raise ComfyError("No node with id, title or class '%s'. Run 'inspect' to list them." % ref)


def parse_value(text):
    if text.startswith("@"):
        with open(text[1:], encoding="utf-8") as f:
            return f.read().rstrip("\n")
    try:
        return json.loads(text)
    except ValueError:
        return text


def apply_overrides(wf, overrides):
    for key, value in overrides.items():
        ref, sep, name = key.rpartition(".")
        if not sep or not ref or not name:
            raise ComfyError("Override '%s' must look like <node id or title>.<input>=<value>." % key)
        node = wf[find_node(wf, ref)]
        inputs = node.setdefault("inputs", {})
        if name not in inputs:
            raise ComfyError("Node '%s' (%s) has no input '%s'. It has: %s" % (
                ref, node.get("class_type"), name, ", ".join(inputs) or "none"))
        inputs[name] = value


def randomize_seeds(wf):
    seeds = {}
    for nid, node in wf.items():
        for name in SEED_INPUTS:
            if isinstance(node.get("inputs", {}).get(name), int):
                node["inputs"][name] = seeds[nid + "." + name] = random.randint(0, 2**50)
    return seeds


def parse_sets(pairs):
    overrides = {}
    for pair in pairs or []:
        key, sep, value = pair.partition("=")
        if not sep:
            raise ComfyError("--set needs KEY=VALUE, got '%s'." % pair)
        overrides[key.strip()] = parse_value(value)
    return overrides


def load_batch(path):
    jobs = []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.lstrip().startswith("["):
        jobs = json.loads(text)
    else:
        jobs = [json.loads(line) for line in text.splitlines() if line.strip()]
    if not all(isinstance(j, dict) for j in jobs):
        raise ComfyError(path + " must hold JSON objects of overrides, one per line or as a list.")
    return jobs


def queue_one(client, wf, front=False):
    body = {"prompt": wf, "client_id": CLIENT_ID}
    if front:
        body["front"] = True
    try:
        resp = client.post("/prompt", body)
    except ComfyError as e:
        err = e.args[0]
        if isinstance(err, dict) and isinstance(err.get("error"), dict):
            raise ComfyError({"rejected": err["error"].get("error"), "node_errors": err["error"].get("node_errors")})
        raise
    return resp


# ----------------------------------------------------------------- history --

def outputs_of(entry):
    files = []
    for nid, node_out in (entry.get("outputs") or {}).items():
        for kind, items in node_out.items():
            if not isinstance(items, list):
                continue
            for item in items:
                if isinstance(item, dict) and "filename" in item:
                    files.append({"node": nid, "kind": kind, "filename": item["filename"],
                                  "subfolder": item.get("subfolder", ""), "type": item.get("type", "output")})
    return files


def summarize(prompt_id, entry):
    status = entry.get("status") or {}
    result = {"prompt_id": prompt_id, "status": status.get("status_str", "unknown"),
              "completed": status.get("completed", False), "outputs": outputs_of(entry)}
    for msg, data in status.get("messages") or []:
        if msg == "execution_error":
            result["error"] = {k: data.get(k) for k in ("node_id", "node_type", "exception_type", "exception_message")}
        if msg == "execution_interrupted":
            result["status"] = "interrupted"
    times = [d.get("timestamp") for _, d in status.get("messages") or [] if isinstance(d, dict) and d.get("timestamp")]
    if len(times) >= 2:
        result["seconds"] = round((max(times) - min(times)) / 1000, 1)
    return result


def queue_position(client, prompt_id):
    q = client.get("/queue")
    for item in q.get("queue_running", []):
        if item[1] == prompt_id:
            return "running"
    for i, item in enumerate(sorted(q.get("queue_pending", []), key=lambda it: it[0])):
        if item[1] == prompt_id:
            return "pending, %d ahead" % i
    return None


def wait_for(client, prompt_ids, timeout, interval, quiet):
    done = {}
    start = time.time()
    last = {}
    while len(done) < len(prompt_ids):
        for pid in prompt_ids:
            if pid in done:
                continue
            hist = client.get("/history/" + pid)
            if hist and pid in hist:
                done[pid] = summarize(pid, hist[pid])
                continue
            if not quiet:
                pos = queue_position(client, pid) or "not in queue yet"
                if last.get(pid) != pos:
                    print(json.dumps({"prompt_id": pid, "waiting": pos}), file=sys.stderr)
                    last[pid] = pos
        if len(done) < len(prompt_ids):
            if timeout and time.time() - start > timeout:
                pending = [p for p in prompt_ids if p not in done]
                raise ComfyError({"timeout_seconds": timeout, "still_waiting": pending, "finished": list(done.values())})
            time.sleep(interval)
    return [done[p] for p in prompt_ids]


def download(client, summary, dest, include_temp):
    saved = []
    for f in summary["outputs"]:
        if f["type"] != "output" and not include_temp:
            continue
        query = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f["subfolder"], "type": f["type"]})
        parts = [p for p in f["subfolder"].replace(chr(92), "/").split("/") if p not in ("", ".", "..")]
        folder = os.path.join(dest, *parts)
        path = os.path.join(folder, os.path.basename(f["filename"]))
        saved.append(path)
        # ComfyUI never reuses an output name, so a file already here is this one.
        if os.path.exists(path):
            continue
        os.makedirs(folder, exist_ok=True)
        # Written beside the final name and renamed only when complete, so an interrupted transfer is retried.
        part = path + ".part"
        try:
            with client.get("/view?" + query, raw=True, timeout=600) as resp, open(part, "wb") as fh:
                expected = resp.headers.get("Content-Length")
                while True:
                    chunk = resp.read(1 << 20)
                    if not chunk:
                        break
                    fh.write(chunk)
            if expected is not None and os.path.getsize(part) != int(expected):
                raise ComfyError({"incomplete_download": f["filename"], "bytes": os.path.getsize(part), "expected": int(expected)})
            os.replace(part, path)
        finally:
            if os.path.exists(part):
                os.remove(part)
    summary["saved"] = saved
    return summary


# ---------------------------------------------------------------- commands --

def cmd_status(client, args):
    stats = client.get("/system_stats")
    q = client.get("/queue")
    out({"comfyui": stats.get("system", {}).get("comfyui_version"),
         "python": stats.get("system", {}).get("python_version", "").split(" ")[0],
         "pytorch": stats.get("system", {}).get("pytorch_version"),
         "devices": [{"name": d.get("name"), "vram_total_gb": round(d.get("vram_total", 0) / 2**30, 1),
                      "vram_free_gb": round(d.get("vram_free", 0) / 2**30, 1)} for d in stats.get("devices", [])],
         "queue_running": len(q.get("queue_running", [])), "queue_pending": len(q.get("queue_pending", []))})


def cmd_models(client, args):
    if args.folder:
        out(client.get("/models/" + urllib.parse.quote(args.folder)))
        return
    folders = client.get("/models")
    if args.all:
        out({f: client.get("/models/" + urllib.parse.quote(f)) for f in folders})
    else:
        out(folders)


def cmd_nodes(client, args):
    info = client.get("/object_info/" + urllib.parse.quote(args.name) if args.name and not args.search else "/object_info")
    if args.name and not args.search:
        out(info)
        return
    names = sorted(info)
    if args.search:
        s = args.search.lower()
        names = [n for n in names if s in n.lower() or s in (info[n].get("display_name") or "").lower()]
    out([{"class": n, "name": info[n].get("display_name"), "category": info[n].get("category")} for n in names])


def cmd_inspect(client, args):
    wf = load_workflow(args.workflow)
    rows = []
    for nid, node in sorted(wf.items(), key=lambda kv: (len(kv[0]), kv[0])):
        settable = {k: v for k, v in node.get("inputs", {}).items() if not (isinstance(v, list) and len(v) == 2 and isinstance(v[1], int))}
        rows.append({"id": nid, "class": node.get("class_type"), "title": node.get("_meta", {}).get("title"), "inputs": settable})
    out(rows)


def cmd_upload(client, args):
    results = []
    for path in args.files:
        boundary = uuid.uuid4().hex
        with open(path, "rb") as f:
            data = f.read()
        parts = []
        fields = {"type": args.type, "overwrite": "true" if args.overwrite else "false"}
        if args.subfolder:
            fields["subfolder"] = args.subfolder
        for k, v in fields.items():
            parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode())
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n"
                      "Content-Type: application/octet-stream\r\n\r\n" % (boundary, os.path.basename(path))).encode())
        parts.append(data + b"\r\n")
        parts.append(("--%s--\r\n" % boundary).encode())
        resp = client.post("/upload/image", b"".join(parts),
                           headers={"Content-Type": "multipart/form-data; boundary=" + boundary}, timeout=600)
        name = resp.get("name")
        if resp.get("subfolder"):
            name = resp["subfolder"] + "/" + name
        results.append({"file": path, "use_as": name, **resp})
    out(results)


def cmd_queue(client, args):
    base = load_workflow(args.workflow)
    common = parse_sets(args.set)
    jobs = load_batch(args.batch) if args.batch else [{}]
    if args.count > 1 and not args.random_seed:
        print(json.dumps({"warning": "--count without --random-seed queues identical jobs; ComfyUI caches them and returns the same output"}), file=sys.stderr)
    queued = []
    for job in jobs:
        for _ in range(args.count):
            wf = json.loads(json.dumps(base))
            apply_overrides(wf, {**common, **job})
            seeds = randomize_seeds(wf) if args.random_seed else {}
            if args.dry_run:
                queued.append({"dry_run": True, "overrides": {**common, **job}, "seeds": seeds})
                continue
            resp = queue_one(client, wf, args.front)
            queued.append({"prompt_id": resp["prompt_id"], "number": resp.get("number"),
                           "overrides": {**common, **job}, "seeds": seeds})
    if args.dry_run:
        out(queued if len(queued) > 1 else {**queued[0], "workflow": wf})
        return
    if not (args.wait or args.download):
        out(queued)
        return
    results = wait_for(client, [q["prompt_id"] for q in queued], args.timeout, args.interval, args.quiet)
    for q, r in zip(queued, results):
        r["overrides"], r["seeds"] = q["overrides"], q["seeds"]
        if args.download and r["completed"]:
            download(client, r, args.download, args.include_temp)
    out(results)
    if any(not r["completed"] for r in results):
        sys.exit(1)


def cmd_wait(client, args):
    results = wait_for(client, args.prompt_ids, args.timeout, args.interval, args.quiet)
    if args.download:
        for r in results:
            if r["completed"]:
                download(client, r, args.download, args.include_temp)
    out(results)
    if any(not r["completed"] for r in results):
        sys.exit(1)


def cmd_download(client, args):
    results = []
    for pid in args.prompt_ids:
        hist = client.get("/history/" + pid)
        if not hist or pid not in hist:
            results.append({"prompt_id": pid, "error": "not in history (still queued, or the server restarted)"})
            continue
        results.append(download(client, summarize(pid, hist[pid]), args.output, args.include_temp))
    out(results)


def cmd_history(client, args):
    hist = client.get("/history?max_items=%d" % args.limit)
    out([summarize(pid, entry) for pid, entry in hist.items()])


def cmd_queue_list(client, args):
    q = client.get("/queue")
    def row(item):
        return {"number": item[0], "prompt_id": item[1], "mine": (item[3] or {}).get("client_id") == CLIENT_ID}
    out({"running": [row(i) for i in q.get("queue_running", [])],
         "pending": [row(i) for i in sorted(q.get("queue_pending", []), key=lambda it: it[0])]})


def cmd_cancel(client, args):
    client.post("/queue", {"delete": args.prompt_ids})
    running = [i[1] for i in client.get("/queue").get("queue_running", [])]
    interrupted = [p for p in args.prompt_ids if p in running]
    for pid in interrupted:
        client.post("/interrupt", {"prompt_id": pid})
    out({"removed_from_queue": [p for p in args.prompt_ids if p not in interrupted], "interrupted": interrupted})


def main():
    p = argparse.ArgumentParser(prog="comfyui_pod.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--url", default=os.environ.get("COMFYUI_URL"), help="ComfyUI address (env COMFYUI_URL)")
    p.add_argument("--token", default=os.environ.get("COMFYUI_TOKEN"), help="access token (env COMFYUI_TOKEN)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="ComfyUI version, GPU memory and queue length")

    s = sub.add_parser("models", help="list model folders, or the files in one folder")
    s.add_argument("folder", nargs="?", help="for example checkpoints, loras, vae, diffusion_models")
    s.add_argument("--all", action="store_true", help="every folder with its files")

    s = sub.add_parser("nodes", help="list installed node classes, or show one class's inputs")
    s.add_argument("name", nargs="?", help="a node class, for example KSampler")
    s.add_argument("--search", help="filter the list by a word")

    s = sub.add_parser("inspect", help="list a workflow's nodes and the inputs you can --set")
    s.add_argument("workflow")

    s = sub.add_parser("upload", help="upload images or videos to ComfyUI's input folder")
    s.add_argument("files", nargs="+")
    s.add_argument("--subfolder", default="")
    s.add_argument("--type", default="input", choices=["input", "temp", "output"])
    s.add_argument("--overwrite", action="store_true")

    def wait_opts(s):
        s.add_argument("--timeout", type=float, default=0, help="give up after this many seconds (default: never)")
        s.add_argument("--interval", type=float, default=2, help="seconds between checks")
        s.add_argument("--download", metavar="DIR", help="save the outputs into DIR when done")
        s.add_argument("--include-temp", action="store_true", help="also save preview (temp) images")
        s.add_argument("--quiet", action="store_true", help="no progress lines on stderr")

    s = sub.add_parser("queue", help="queue an API-format workflow, with overrides, once or as a batch")
    s.add_argument("workflow", help="workflow JSON in API format (Workflow > Export (API))")
    s.add_argument("--set", action="append", metavar="NODE.INPUT=VALUE",
                   help="override an input; NODE is a node id, title or unique class; VALUE is JSON or text, @file reads a file")
    s.add_argument("--batch", metavar="FILE", help="JSONL (or a JSON list) of override objects; one job per entry")
    s.add_argument("--count", type=int, default=1, help="queue each job this many times")
    s.add_argument("--random-seed", action="store_true", help="give every seed/noise_seed input a new random value per job")
    s.add_argument("--front", action="store_true", help="put the jobs at the front of the queue")
    s.add_argument("--wait", action="store_true", help="wait for the jobs and print their results")
    s.add_argument("--dry-run", action="store_true", help="print what would be queued without queueing it")
    wait_opts(s)

    s = sub.add_parser("wait", help="wait for queued jobs and print their outputs")
    s.add_argument("prompt_ids", nargs="+")
    wait_opts(s)

    s = sub.add_parser("download", help="save a finished job's outputs")
    s.add_argument("prompt_ids", nargs="+")
    s.add_argument("-o", "--output", default=".", help="folder to save into")
    s.add_argument("--include-temp", action="store_true")

    s = sub.add_parser("history", help="recent finished jobs")
    s.add_argument("--limit", type=int, default=10)

    sub.add_parser("list", help="the queue: what is running and what is waiting")

    s = sub.add_parser("cancel", help="remove jobs from the queue, or stop them if running")
    s.add_argument("prompt_ids", nargs="+")

    args = p.parse_args()
    handlers = {"status": cmd_status, "models": cmd_models, "nodes": cmd_nodes, "inspect": cmd_inspect,
                "upload": cmd_upload, "queue": cmd_queue, "wait": cmd_wait, "download": cmd_download,
                "history": cmd_history, "list": cmd_queue_list, "cancel": cmd_cancel}
    try:
        client = None if args.cmd == "inspect" else Client(args.url, args.token)
        handlers[args.cmd](client, args)
    except ComfyError as e:
        print(json.dumps({"error": e.args[0]}), file=sys.stderr)
        sys.exit(2)
    except (OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
