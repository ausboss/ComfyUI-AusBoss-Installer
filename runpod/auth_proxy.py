#!/usr/bin/env python3
"""Token gate in front of ComfyUI.

Listens on the public port and forwards to ComfyUI on a loopback port, but
only for requests that carry the token: an "Authorization: Bearer <token>"
header (agents and scripts), the cookie this proxy sets after a browser signs
in, or ?token=<token> in the URL (which signs the browser in and is then
stripped from the address bar). Everything else gets a sign-in page or a 401.
"""

import asyncio
import hashlib
import hmac
import html
import logging
import os
import sys
from urllib.parse import quote

import aiohttp
from aiohttp import web

TOKEN = os.environ.get("COMFYUI_TOKEN", "")
LISTEN_HOST = os.environ.get("PROXY_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("PROXY_PORT", "8188"))
UPSTREAM = os.environ.get("COMFYUI_UPSTREAM", "http://127.0.0.1:8189")
COOKIE = "comfyui_auth"
COOKIE_VALUE = hashlib.sha256(("comfyui-auth-cookie:" + TOKEN).encode()).hexdigest()
COOKIE_MAX_AGE = 30 * 24 * 3600
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "transfer-encoding", "upgrade", "host", "content-length",
}

log = logging.getLogger("auth-proxy")

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ComfyUI sign in</title>
<style>
body{font-family:system-ui,sans-serif;background:#1c1c1c;color:#ddd;display:flex;
min-height:100vh;align-items:center;justify-content:center;margin:0}
form{background:#262626;padding:28px;border-radius:10px;width:min(360px,90vw)}
h1{font-size:18px;margin:0 0 14px}p{font-size:13px;color:#aaa;line-height:1.5}
input{width:100%;box-sizing:border-box;padding:10px;border-radius:6px;border:1px solid #444;
background:#1c1c1c;color:#eee;font-size:14px}
button{margin-top:12px;width:100%;padding:10px;border:0;border-radius:6px;background:#4a7dff;
color:#fff;font-size:14px;cursor:pointer}.err{color:#ff7b7b}
</style></head><body><form method="post" action="/__login">
<h1>ComfyUI</h1><p>This pod is private. Paste the access token you set when you deployed it
(the COMFYUI_TOKEN variable).</p>{error}
<input type="password" name="token" autocomplete="current-password" autofocus placeholder="Access token">
<input type="hidden" name="next" value="{next}">
<button type="submit">Open ComfyUI</button></form></body></html>"""

STARTING = """<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="5">
<title>ComfyUI is starting</title></head>
<body style="font-family:system-ui,sans-serif;background:#1c1c1c;color:#ddd;padding:40px">
<h2>ComfyUI is starting</h2><p>This page reloads every 5 seconds.</p></body></html>"""


def token_ok(candidate):
    return bool(candidate) and hmac.compare_digest(candidate.encode(), TOKEN.encode())


def authorized(request):
    auth = request.headers.get("Authorization", "")
    if auth[:7].lower() == "bearer " and token_ok(auth[7:].strip()):
        return True
    cookie = request.cookies.get(COOKIE, "")
    if cookie and hmac.compare_digest(cookie.encode(), COOKIE_VALUE.encode()):
        return True
    return token_ok(request.query.get("token", ""))


def wants_html(request):
    return request.method == "GET" and "text/html" in request.headers.get("Accept", "")


def is_https(request):
    return request.headers.get("X-Forwarded-Proto", request.scheme) == "https"


def set_cookie(response, request):
    response.set_cookie(COOKIE, COOKIE_VALUE, max_age=COOKIE_MAX_AGE, path="/",
                        httponly=True, samesite="Lax", secure=is_https(request))


def safe_next(value):
    return value if value.startswith("/") and not value.startswith("//") else "/"


def upstream_headers(request):
    headers = {k: v for k, v in request.headers.items()
               if k.lower() not in HOP_BY_HOP and k.lower() not in ("authorization", "cookie")}
    # Keep the public Host so ComfyUI's same-origin check compares it with the
    # browser's Origin instead of with 127.0.0.1.
    headers["Host"] = request.host
    cookies = [f"{k}={v}" for k, v in request.cookies.items() if k != COOKIE]
    if cookies:
        headers["Cookie"] = "; ".join(cookies)
    peer = request.remote or ""
    prior = request.headers.get("X-Forwarded-For")
    headers["X-Forwarded-For"] = f"{prior}, {peer}" if prior else peer
    return headers


def upstream_url(request):
    query = [(k, v) for k, v in request.query.items() if k != "token"]
    url = UPSTREAM + request.path
    return url, query


async def login(request):
    if request.method == "GET":
        nxt = html.escape(safe_next(request.query.get("next", "/")))
        return web.Response(text=PAGE.replace("{error}", "").replace("{next}", nxt), content_type="text/html")
    form = await request.post()
    nxt = safe_next(str(form.get("next", "/")))
    if not token_ok(str(form.get("token", ""))):
        await asyncio.sleep(1)
        body = PAGE.replace("{error}", '<p class="err">That token is not right.</p>').replace("{next}", html.escape(nxt))
        return web.Response(status=401, text=body, content_type="text/html")
    response = web.HTTPFound(nxt)
    set_cookie(response, request)
    raise response


async def logout(request):
    response = web.HTTPFound("/__login")
    response.del_cookie(COOKIE, path="/")
    raise response


async def proxy_ws(request, session):
    url, query = upstream_url(request)
    url = "ws" + url[4:]
    headers = upstream_headers(request)
    for name in ("Sec-WebSocket-Key", "Sec-WebSocket-Version", "Sec-WebSocket-Extensions"):
        headers.pop(name, None)
    try:
        upstream = await session.ws_connect(url, params=query, headers=headers,
                                            max_msg_size=0, autoping=True)
    except aiohttp.ClientError:
        return web.Response(status=503, text="ComfyUI is starting")
    client = web.WebSocketResponse(max_msg_size=0, autoping=True)
    await client.prepare(request)

    async def pump(src, dst):
        async for msg in src:
            if msg.type == aiohttp.WSMsgType.TEXT:
                await dst.send_str(msg.data)
            elif msg.type == aiohttp.WSMsgType.BINARY:
                await dst.send_bytes(msg.data)
            else:
                break

    tasks = [asyncio.create_task(pump(upstream, client)), asyncio.create_task(pump(client, upstream))]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in tasks:
            task.cancel()
        await upstream.close()
        await client.close()
    return client


async def handle(request):
    if request.path == "/__login":
        return await login(request)
    if request.path == "/__logout":
        return await logout(request)
    if not authorized(request):
        if wants_html(request):
            raise web.HTTPFound("/__login?next=" + quote(request.path_qs, safe=""))
        return web.json_response({"error": "unauthorized", "hint": "send Authorization: Bearer <COMFYUI_TOKEN>"},
                                 status=401, headers={"WWW-Authenticate": "Bearer"})

    # A browser that arrived with ?token= gets the cookie and a clean address bar.
    if "token" in request.query and wants_html(request):
        query = [(k, v) for k, v in request.query.items() if k != "token"]
        target = str(request.rel_url.with_query(query))
        response = web.HTTPFound(target)
        set_cookie(response, request)
        raise response

    session = request.app["session"]
    if request.headers.get("Upgrade", "").lower() == "websocket":
        return await proxy_ws(request, session)

    url, query = upstream_url(request)
    try:
        upstream = await session.request(
            request.method, url, params=query, headers=upstream_headers(request),
            data=request.content if request.body_exists else None,
            allow_redirects=False)
    except aiohttp.ClientConnectionError:
        if wants_html(request):
            return web.Response(status=503, text=STARTING, content_type="text/html")
        return web.json_response({"error": "ComfyUI is starting"}, status=503, headers={"Retry-After": "5"})

    async with upstream:
        response = web.StreamResponse(status=upstream.status, reason=upstream.reason)
        for k, v in upstream.headers.items():
            if k.lower() not in HOP_BY_HOP:
                response.headers.add(k, v)
        if upstream.content_length is not None:
            response.content_length = upstream.content_length
        await response.prepare(request)
        async for chunk in upstream.content.iter_chunked(1 << 16):
            await response.write(chunk)
        await response.write_eof()
        return response


async def on_startup(app):
    app["session"] = aiohttp.ClientSession(
        timeout=aiohttp.ClientTimeout(total=None, sock_connect=5),
        auto_decompress=False, cookie_jar=aiohttp.DummyCookieJar())


async def on_cleanup(app):
    await app["session"].close()


def main():
    logging.basicConfig(level=logging.INFO, format="[auth-proxy] %(message)s")
    if not TOKEN:
        sys.exit("COMFYUI_TOKEN is empty; refusing to start an open proxy.")
    if len(TOKEN) < 16:
        log.warning("COMFYUI_TOKEN is shorter than 16 characters; use a long random token.")
    app = web.Application(client_max_size=0)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.router.add_route("*", "/{tail:.*}", handle)
    log.info("listening on %s:%d, forwarding to %s", LISTEN_HOST, LISTEN_PORT, UPSTREAM)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None, print=None)


if __name__ == "__main__":
    main()
