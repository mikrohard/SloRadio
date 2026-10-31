#!/usr/bin/env python3
"""
SloRadio station inventory (Phase 0 of the MobileVLCKit -> FFmpeg migration).

Probes every station returned by the SloRadio stations API and records what a
new player has to support: transport (HTTP/ICY/HLS, TLS issues, redirects),
station playlist formats, containers & codecs (via ffprobe), and metadata
(ICY StreamTitle bytes + charset, ICY headers, HLS ID3 / EXTINF, Ogg comments).

A raw socket HTTP client is used on purpose so that non-HTTP status lines
("ICY 200 OK"), exact header bytes and invalid TLS certificates are visible.

Usage:
    python3 Scripts/station_inventory.py OUTPUT_DIR [--url STATIONS_API] [--workers N] [--only NAME]

Requires: python3, ffprobe (brew install ffmpeg).
Writes OUTPUT_DIR/inventory.json, OUTPUT_DIR/summary.md and per-station samples.
"""

import argparse
import collections
import concurrent.futures
import json
import os
import re
import socket
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request

STATIONS_API = "https://iphone.jernej.org/sloradio/stations.php"
USER_AGENT = "SloRadio-Inventory/1.0"
VLC_USER_AGENT = "VLC/3.0.20 LibVLC/3.0.20"
CONNECT_TIMEOUT = 10.0
STREAM_READ_SECONDS = 12.0
STREAM_MAX_BYTES = 768 * 1024
DOC_MAX_BYTES = 512 * 1024
MAX_REDIRECTS = 6

PLAYLIST_EXTS = (".pls", ".m3u", ".m3u8", ".asx", ".xspf", ".wax", ".wvx")
SLO_CP1250 = set("čšžćđČŠŽĆĐ")


# --------------------------------------------------------------------------- HTTP

class FetchResult:
    def __init__(self):
        self.url = None
        self.status_line = None
        self.status_code = None
        self.protocol = None            # "HTTP/1.1", "HTTP/1.0", "ICY", ...
        self.headers = {}               # lower-case keys
        self.raw_headers = []
        self.body = b""
        self.tls = None                 # None (plain), "ok", "invalid-cert: ..."
        self.error = None
        self.elapsed = 0.0
        self.time_to_first_byte = None


def _decode_chunked(data):
    out = bytearray()
    pos = 0
    while pos < len(data):
        end = data.find(b"\r\n", pos)
        if end < 0:
            break
        try:
            size = int(data[pos:end].split(b";")[0].strip() or b"0", 16)
        except ValueError:
            return bytes(data)  # not really chunked
        if size == 0:
            break
        start = end + 2
        out += data[start:start + size]
        pos = start + size + 2
    return bytes(out)


def raw_get(url, max_bytes, max_seconds, user_agent=USER_AGENT, icy=True):
    r = FetchResult()
    r.url = url
    t0 = time.time()
    p = urllib.parse.urlsplit(url)
    host = p.hostname
    https = p.scheme == "https"
    port = p.port or (443 if https else 80)
    path = p.path or "/"
    if p.query:
        path += "?" + p.query
    host_hdr = host if p.port is None else f"{host}:{p.port}"
    req = (f"GET {path} HTTP/1.1\r\nHost: {host_hdr}\r\nUser-Agent: {user_agent}\r\n"
           f"Accept: */*\r\n" + ("Icy-MetaData: 1\r\n" if icy else "") +
           "Connection: close\r\n\r\n").encode("latin-1")
    sock = None
    try:
        sock = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
        if https:
            ctx = ssl.create_default_context()
            try:
                s2 = ctx.wrap_socket(sock, server_hostname=host)
                r.tls = "ok"
            except ssl.SSLCertVerificationError as e:
                sock.close()
                sock = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
                ctx = ssl._create_unverified_context()
                s2 = ctx.wrap_socket(sock, server_hostname=host)
                r.tls = f"invalid-cert: {e.verify_message}"
            sock = s2
        sock.settimeout(CONNECT_TIMEOUT)
        sock.sendall(req)
        buf = bytearray()
        header_end = -1
        while header_end < 0:
            chunk = sock.recv(16384)
            if not chunk:
                break
            if r.time_to_first_byte is None:
                r.time_to_first_byte = round(time.time() - t0, 3)
            buf += chunk
            for sep in (b"\r\n\r\n", b"\n\n"):
                i = buf.find(sep)
                if i >= 0 and (header_end < 0 or i < header_end):
                    header_end = i
                    sep_len = len(sep)
            if len(buf) > 65536 and header_end < 0:
                break
        if header_end < 0:
            r.error = "no-http-header"
            r.body = bytes(buf[:256])
            return r
        head = buf[:header_end].decode("latin-1", "replace")
        body = bytearray(buf[header_end + sep_len:])
        lines = re.split(r"\r?\n", head)
        r.status_line = lines[0].strip()
        m = re.match(r"(\S+)\s+(\d{3})", r.status_line)
        if m:
            r.protocol = m.group(1).split("/")[0] if m.group(1).upper().startswith("ICY") else m.group(1)
            r.status_code = int(m.group(2))
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                r.raw_headers.append(line)
                r.headers[k.strip().lower()] = v.strip()
        if r.status_code and 300 <= r.status_code < 400:
            r.body = bytes(body)
            return r
        clen = r.headers.get("content-length")
        limit = max_bytes
        if clen and clen.isdigit():
            limit = min(limit, int(clen))
        while len(body) < limit and time.time() - t0 < max_seconds:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            body += chunk
        body = bytes(body[:limit]) if not clen else bytes(body)
        if "chunked" in r.headers.get("transfer-encoding", "").lower():
            body = _decode_chunked(body)
        r.body = body
    except Exception as e:  # noqa: BLE001 - we want every failure recorded
        r.error = f"{type(e).__name__}: {e}"
    finally:
        r.elapsed = round(time.time() - t0, 2)
        if sock:
            try:
                sock.close()
            except Exception:
                pass
    return r


def fetch_follow(url, max_bytes, max_seconds, user_agent=USER_AGENT, icy=True):
    chain = []
    for _ in range(MAX_REDIRECTS + 1):
        r = raw_get(url, max_bytes, max_seconds, user_agent, icy)
        chain.append({"url": url, "status": r.status_line, "tls": r.tls, "error": r.error})
        if r.status_code in (301, 302, 303, 307, 308) and "location" in r.headers:
            url = urllib.parse.urljoin(url, r.headers["location"])
            continue
        return r, chain
    return r, chain


# --------------------------------------------------------------------------- sniffing

def sniff_kind(url, ctype, body):
    head = body[:2048].lstrip(b"\xef\xbb\xbf \r\n\t")
    low = head.lower()
    ctype = (ctype or "").lower()
    path = urllib.parse.urlsplit(url).path.lower()
    if head.startswith(b"#EXTM3U") and (b"#EXT-X-" in body[:8192]):
        return "hls"
    if low.startswith(b"[playlist]"):
        return "pls"
    if low.startswith(b"<asx") or (b"<asx" in low[:200]):
        return "asx"
    if b"<playlist" in low[:300] and b"xspf" in low[:500]:
        return "xspf"
    if head.startswith(b"#EXTM3U") or ("mpegurl" in ctype and not head.startswith(b"ID3")):
        return "m3u"
    if path.endswith((".m3u", ".pls", ".asx", ".xspf")) and re.match(rb"^(https?|mms|rtsp|rtmp)://", head):
        return "m3u"
    if re.match(rb"^(https?|mms|rtsp|rtmp)://\S+\s*$", head[:1024]) and len(body) < 4096:
        return "m3u"  # bare URL list
    if head.startswith(b"<!doctype html") or head.startswith(b"<html"):
        return "html"
    return "stream"


def parse_playlist(kind, body, base):
    text = body.decode("utf-8", "replace")
    urls = []
    if kind == "pls":
        for m in re.finditer(r"(?im)^\s*File\d+\s*=\s*(\S+)", text):
            urls.append(m.group(1))
    elif kind in ("asx",):
        urls = re.findall(r'(?i)<ref\s+href\s*=\s*"([^"]+)"', text)
    elif kind == "xspf":
        urls = re.findall(r"(?i)<location>\s*([^<\s]+)\s*</location>", text)
    else:
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                urls.append(line)
    return [urllib.parse.urljoin(base, u) for u in urls]


def detect_charset(raw):
    if not raw:
        return "empty"
    if all(b < 0x80 for b in raw):
        return "ascii"
    try:
        s = raw.decode("utf-8")
        # double-encoded utf-8 (utf-8 bytes read as latin-1/cp1250 then re-encoded)
        if re.search("[ÃÄÅ][\u0080-¿]", s) or re.search("Ä[\u008c\u008dšž]", s):
            return "utf-8 (double-encoded?)"
        return "utf-8"
    except UnicodeDecodeError:
        pass
    cp = raw.decode("cp1250", "replace")
    l1 = raw.decode("latin-1", "replace")
    cp_score = sum(1 for c in cp if c in SLO_CP1250)
    l1_score = sum(1 for c in l1 if c in "àáâãäåæçèéêëìíîïñòóôõöùúûüýÿ")
    if cp_score >= l1_score and cp_score > 0:
        return "cp1250"
    if l1_score > 0:
        return "latin-1"
    return "8-bit-unknown"


def best_decode(raw, charset):
    if charset.startswith("utf-8") or charset == "ascii":
        return raw.decode("utf-8", "replace")
    if charset == "cp1250":
        return raw.decode("cp1250", "replace")
    return raw.decode("latin-1", "replace")


def deinterleave_icy(body, metaint):
    audio = bytearray()
    blocks = []
    pos = 0
    n = len(body)
    while pos < n:
        take = min(metaint, n - pos)
        audio += body[pos:pos + take]
        pos += take
        if take < metaint or pos >= n:
            break
        length = body[pos] * 16
        pos += 1
        if length:
            meta = body[pos:pos + length]
            if len(meta) < length:
                break
            blocks.append({"audio_offset": len(audio), "raw": meta.rstrip(b"\x00")})
            pos += length
    return bytes(audio), blocks


def parse_icy_block(raw):
    fields = {}
    for m in re.finditer(rb"(\w+)='(.*?)';(?=\w+=|\s*$)", raw, re.S):
        fields[m.group(1).decode("latin-1")] = m.group(2)
    if not fields:
        m = re.search(rb"StreamTitle='(.*)", raw, re.S)
        if m:
            fields["StreamTitle"] = m.group(1).rstrip(b"';\x00")
    return fields


def ffprobe_file(path):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path],
            capture_output=True, timeout=60)
        data = json.loads(out.stdout or b"{}")
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}
    res = {"format": data.get("format", {}).get("format_name"),
           "format_tags": data.get("format", {}).get("tags", {}),
           "streams": []}
    for s in data.get("streams", []):
        res["streams"].append({k: s.get(k) for k in (
            "codec_type", "codec_name", "profile", "sample_rate", "channels",
            "channel_layout", "bit_rate", "codec_tag_string") if s.get(k) is not None}
            | ({"tags": s["tags"]} if s.get("tags") else {}))
    if out.stderr:
        res["stderr"] = out.stderr.decode("utf-8", "replace")[-400:]
    return res


# --------------------------------------------------------------------------- probes

def probe_hls(url, body, outdir, rec):
    text = body.decode("utf-8", "replace")
    hls = {"master": "#EXT-X-STREAM-INF" in text, "variants": []}
    media_url, media_text = url, text
    if hls["master"]:
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if line.startswith("#EXT-X-STREAM-INF"):
                attrs = dict(re.findall(r'([A-Z\-]+)=("[^"]*"|[^,]*)', line))
                uri = next((l.strip() for l in lines[i + 1:] if l.strip() and not l.startswith("#")), None)
                hls["variants"].append({"bandwidth": int(attrs.get("BANDWIDTH", "0") or 0),
                                        "codecs": attrs.get("CODECS", "").strip('"'),
                                        "uri": urllib.parse.urljoin(url, uri) if uri else None})
        hls["audio_renditions"] = len(re.findall(r"#EXT-X-MEDIA:.*TYPE=AUDIO", text))
        if hls["variants"]:
            best = max(hls["variants"], key=lambda v: v["bandwidth"])
            r, _ = fetch_follow(best["uri"], DOC_MAX_BYTES, 15, icy=False)
            media_url, media_text = best["uri"], r.body.decode("utf-8", "replace")
    segs = [urllib.parse.urljoin(media_url, l.strip()) for l in media_text.splitlines()
            if l.strip() and not l.startswith("#")]
    exts = collections.Counter(os.path.splitext(urllib.parse.urlsplit(s).path)[1].lower() or "(none)" for s in segs)
    hls.update({
        "segment_exts": dict(exts),
        "segments": len(segs),
        "fmp4": "#EXT-X-MAP" in media_text,
        "encrypted": re.findall(r"#EXT-X-KEY:METHOD=([A-Z0-9\-]+)", media_text)[:1],
        "target_duration": (re.findall(r"#EXT-X-TARGETDURATION:(\d+)", media_text) or [None])[0],
        "program_date_time": "#EXT-X-PROGRAM-DATE-TIME" in media_text,
        "daterange": "#EXT-X-DATERANGE" in media_text,
        "extinf_titles": [t.strip() for t in re.findall(r"#EXTINF:[^,]*,(.*)", media_text) if t.strip()][:3],
        "live": "#EXT-X-ENDLIST" not in media_text,
    })
    if segs:
        seg = segs[-1]
        if hls["fmp4"]:
            m = re.search(r'#EXT-X-MAP:URI="([^"]+)"', media_text)
            init = fetch_follow(urllib.parse.urljoin(media_url, m.group(1)), 1 << 20, 15, icy=False)[0].body if m else b""
        else:
            init = b""
        r, _ = fetch_follow(seg, 4 << 20, 20, icy=False)
        ext = os.path.splitext(urllib.parse.urlsplit(seg).path)[1] or ".bin"
        path = os.path.join(outdir, "segment" + ext)
        with open(path, "wb") as f:
            f.write(init + r.body)
        probe = ffprobe_file(path)
        hls["segment_probe"] = probe
        hls["id3_in_segment"] = r.body[:3] == b"ID3" or any(
            s.get("codec_name") == "timed_id3" or (s.get("codec_type") == "data") for s in probe.get("streams", []))
    rec["hls"] = hls
    sp = hls.get("segment_probe", {})
    rec["container"] = "hls/" + (sp.get("format") or "?")
    rec["audio"] = next((s for s in sp.get("streams", []) if s.get("codec_type") == "audio"), None)


def probe_stream(r, outdir, rec):
    body = r.body
    metaint = r.headers.get("icy-metaint")
    icy = {k: v for k, v in r.headers.items() if k.startswith("icy-") or k.startswith("ice-")}
    rec["icy_headers"] = icy
    audio = body
    if metaint and metaint.isdigit() and int(metaint) > 0:
        audio, blocks = deinterleave_icy(body, int(metaint))
        titles = []
        for b in blocks:
            f = parse_icy_block(b["raw"])
            st = f.get("StreamTitle")
            cs = detect_charset(st) if st is not None else "n/a"
            titles.append({"audio_offset": b["audio_offset"],
                           "fields": sorted(f.keys()),
                           "charset": cs,
                           "title": best_decode(st, cs) if st is not None else None,
                           "raw_hex": st.hex() if st and cs not in ("ascii", "utf-8") else None})
        rec["icy_metadata"] = {"metaint": int(metaint), "blocks": titles}
    path = os.path.join(outdir, "sample.bin")
    with open(path, "wb") as f:
        f.write(audio)
    probe = ffprobe_file(path)
    rec["probe"] = probe
    rec["container"] = probe.get("format")
    rec["audio"] = next((s for s in probe.get("streams", []) if s.get("codec_type") == "audio"), None)
    rec["bytes_read"] = len(body)
    rec["read_seconds"] = r.elapsed
    if r.elapsed:
        rec["throughput_kbps"] = round(len(body) * 8 / 1000 / r.elapsed, 1)


def probe_station(st, outroot):
    sid = st["id"]
    outdir = os.path.join(outroot, "samples", f"{sid}")
    os.makedirs(outdir, exist_ok=True)
    rec = {"id": sid, "name": st["name"], "url": st["url"], "playlist": None}
    url = st["url"]
    scheme = urllib.parse.urlsplit(url).scheme.lower()
    rec["scheme"] = scheme
    if scheme not in ("http", "https"):
        rec["error"] = f"unsupported scheme {scheme}"
        return rec
    for depth in range(3):
        r, chain = fetch_follow(url, STREAM_MAX_BYTES, STREAM_READ_SECONDS)
        if depth == 0:
            rec["redirects"] = chain[:-1]
        if r.error or (r.status_code and r.status_code >= 400) or not r.status_code:
            # retry once with the VLC user agent - some servers gate on it
            r2, _ = fetch_follow(url, STREAM_MAX_BYTES, STREAM_READ_SECONDS, user_agent=VLC_USER_AGENT)
            if not r2.error and r2.status_code and r2.status_code < 400:
                rec["needs_vlc_user_agent"] = True
                r = r2
        rec.update({"final_url": r.url, "status_line": r.status_line, "protocol": r.protocol,
                    "tls": r.tls, "content_type": r.headers.get("content-type"),
                    "server": r.headers.get("server"), "ttfb": r.time_to_first_byte,
                    "error": r.error})
        if r.error or not r.status_code or r.status_code >= 400:
            rec["error"] = r.error or f"HTTP {r.status_code}"
            return rec
        kind = sniff_kind(r.url, r.headers.get("content-type"), r.body)
        if kind == "hls":
            rec["kind"] = "hls"
            probe_hls(r.url, r.body, outdir, rec)
            return rec
        if kind in ("pls", "m3u", "asx", "xspf"):
            entries = parse_playlist(kind, r.body, r.url)
            rec["playlist"] = {"type": kind, "entries": entries[:10], "count": len(entries)}
            if not entries:
                rec["error"] = f"empty {kind} playlist"
                return rec
            url = entries[0]
            if urllib.parse.urlsplit(url).scheme.lower() not in ("http", "https"):
                rec["error"] = f"playlist entry scheme {urllib.parse.urlsplit(url).scheme}"
                return rec
            continue
        if kind == "html":
            rec["kind"] = "html"
            rec["error"] = "got HTML instead of a stream"
            return rec
        rec["kind"] = "progressive"
        probe_stream(r, outdir, rec)
        return rec
    rec["error"] = "playlist nesting too deep"
    return rec


# --------------------------------------------------------------------------- report

def codec_label(rec):
    a = rec.get("audio") or {}
    name = a.get("codec_name")
    if not name:
        return "unknown"
    prof = a.get("profile")
    return f"{name} ({prof})" if prof and prof not in ("unknown",) else name


def summarize(records):
    md = []
    ok = [r for r in records if not r.get("error")]
    md.append(f"# Station inventory\n\nProbed {len(records)} stations, {len(ok)} OK, "
              f"{len(records) - len(ok)} failed. Generated {time.strftime('%Y-%m-%d %H:%M')}.\n")

    def table(title, counter):
        md.append(f"\n## {title}\n\n| Value | Stations |\n|---|---|")
        for k, v in counter.most_common():
            md.append(f"| {k} | {v} |")

    table("Delivery", collections.Counter(r.get("kind", "error") for r in records))
    table("Initial URL scheme", collections.Counter(r.get("scheme") for r in records))
    table("Response protocol (status line)", collections.Counter(r.get("protocol") or "-" for r in ok))
    table("Station playlist wrapper", collections.Counter((r.get("playlist") or {}).get("type", "none") for r in records))
    table("Container", collections.Counter(r.get("container") or "?" for r in ok))
    table("Codec", collections.Counter(codec_label(r) for r in ok))
    table("Sample rate / channels", collections.Counter(
        f"{(r.get('audio') or {}).get('sample_rate')} Hz / {(r.get('audio') or {}).get('channels')} ch" for r in ok))
    table("Server", collections.Counter((r.get("server") or "?").split("/")[0] for r in ok))
    prog = [r for r in ok if r.get("kind") == "progressive"]
    table("ICY metadata (progressive)", collections.Counter(
        "icy-metaint, title seen" if (r.get("icy_metadata") and r["icy_metadata"]["blocks"]) else
        "icy-metaint, no title in sample" if r.get("icy_metadata") else "no icy-metaint" for r in prog))
    table("StreamTitle charset", collections.Counter(
        b["charset"] for r in prog for b in (r.get("icy_metadata") or {}).get("blocks", [])[:1]))
    hls = [r for r in ok if r.get("kind") == "hls"]
    if hls:
        table("HLS segment type", collections.Counter(
            ",".join(r["hls"]["segment_exts"].keys()) + (" (fMP4)" if r["hls"]["fmp4"] else "") for r in hls))
        table("HLS metadata", collections.Counter(
            ("ID3 " if r["hls"].get("id3_in_segment") else "") + ("EXTINF-titles " if r["hls"]["extinf_titles"] else "") +
            ("PDT " if r["hls"]["program_date_time"] else "") + ("DATERANGE" if r["hls"]["daterange"] else "") or "none"
            for r in hls))
    flags = []
    for r in records:
        notes = []
        if r.get("tls", "") and str(r.get("tls")).startswith("invalid-cert"):
            notes.append(r["tls"])
        if r.get("protocol") == "ICY":
            notes.append("ICY status line")
        if r.get("needs_vlc_user_agent"):
            notes.append("needs VLC user agent")
        if any(str(c.get("url", "")).startswith("https") for c in r.get("redirects", [])) and r.get("scheme") == "http":
            notes.append("redirects http->https")
        for b in (r.get("icy_metadata") or {}).get("blocks", [])[:1]:
            if b["charset"] not in ("ascii", "utf-8"):
                notes.append(f"title charset {b['charset']}")
        if r.get("error"):
            notes.append("ERROR: " + r["error"])
        if notes:
            flags.append((r, notes))
    md.append("\n## Stations needing attention\n\n| Station | URL | Notes |\n|---|---|---|")
    for r, notes in flags:
        md.append(f"| {r['name']} | `{r['url']}` | {'; '.join(notes)} |")
    md.append("\n## All stations\n\n| Station | Delivery | Container | Codec | Rate/ch | Metadata sample |\n|---|---|---|---|---|---|")
    for r in sorted(records, key=lambda x: x["name"].lower()):
        a = r.get("audio") or {}
        meta = ""
        blocks = (r.get("icy_metadata") or {}).get("blocks") or []
        if blocks:
            meta = (blocks[0].get("title") or "").replace("|", "\\|")[:60]
        elif r.get("hls", {}).get("extinf_titles"):
            meta = "EXTINF: " + r["hls"]["extinf_titles"][0][:50]
        md.append(f"| {r['name']} | {r.get('kind', 'error')}{' via ' + r['playlist']['type'] if r.get('playlist') else ''} | "
                  f"{r.get('container') or '-'} | {codec_label(r)} | {a.get('sample_rate', '-')}/{a.get('channels', '-')} | "
                  f"{meta or ('ERROR: ' + r['error'] if r.get('error') else '')} |")
    return "\n".join(md) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output")
    ap.add_argument("--url", default=STATIONS_API)
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--only", help="substring filter on station name")
    args = ap.parse_args()
    os.makedirs(args.output, exist_ok=True)
    with urllib.request.urlopen(args.url, timeout=30) as resp:
        stations = json.load(resp)["stations"]
    if args.only:
        stations = [s for s in stations if args.only.lower() in s["name"].lower()]
    print(f"Probing {len(stations)} stations...", file=sys.stderr)
    records = []
    with concurrent.futures.ThreadPoolExecutor(args.workers) as ex:
        futs = {ex.submit(probe_station, s, args.output): s for s in stations}
        for i, fut in enumerate(concurrent.futures.as_completed(futs), 1):
            s = futs[fut]
            try:
                rec = fut.result()
            except Exception as e:  # noqa: BLE001
                rec = {"id": s["id"], "name": s["name"], "url": s["url"], "error": f"crash: {e!r}"}
            records.append(rec)
            print(f"[{i}/{len(stations)}] {rec['name']}: {rec.get('kind', '-')} {codec_label(rec)}"
                  f"{' ERROR ' + rec['error'] if rec.get('error') else ''}", file=sys.stderr)
    records.sort(key=lambda r: int(r["id"]))
    with open(os.path.join(args.output, "inventory.json"), "w") as f:
        json.dump(records, f, indent=1, ensure_ascii=False, default=str)
    with open(os.path.join(args.output, "summary.md"), "w") as f:
        f.write(summarize(records))
    print(f"Wrote {args.output}/inventory.json and summary.md", file=sys.stderr)


if __name__ == "__main__":
    main()
