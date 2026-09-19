#!/usr/bin/env python3
"""Usage report for Screen Off.

Two sources, both already produced by normal operation — the app sends nothing extra for this:

1. GitHub Releases download counts (cumulative). Each run appends a snapshot so later runs can show
   the delta; GitHub itself only ever reports a running total.
2. The US1 update log, which records one line per update probe. Its nginx format stores no client
   address, so this reports request volume and the anonymous profile fields Sparkle attaches — never
   individual users.

Usage:
    Script/usage_report.py                     # GitHub only
    Script/usage_report.py --host root@<update-host> --ssh-key ~/.ssh/id_ed25519
    Script/usage_report.py --host root@<update-host> --ssh-key ~/.ssh/id_ed25519 --days 30
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = ROOT / "build" / "usage" / "github-snapshots.jsonl"
REMOTE_LOG = "/var/log/nginx/screenoff-updates.log"
LOG_LINE = re.compile(r'^(?P<time>\S+) (?P<status>\d{3}) "(?P<request>[^"]*)" "(?P<agent>[^"]*)"')


def fetch_github(repo: str) -> list[dict]:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/releases",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "screenoff-usage-report"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
    if isinstance(payload, dict):
        raise RuntimeError(payload.get("message", "unexpected response"))
    return payload


def snapshot_github(releases: list[dict]) -> dict:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    record = {
        "at": now,
        "releases": {
            release["tag_name"]: {
                asset["name"]: asset["download_count"] for asset in release.get("assets", [])
            }
            for release in releases
        },
    }
    SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
    previous = None
    if SNAPSHOT.exists():
        lines = [line for line in SNAPSHOT.read_text().splitlines() if line.strip()]
        if lines:
            previous = json.loads(lines[-1])
    with SNAPSHOT.open("a") as handle:
        handle.write(json.dumps(record) + "\n")
    return {"current": record, "previous": previous}


def report_github(snapshots: dict) -> None:
    current, previous = snapshots["current"], snapshots["previous"]
    print("下载量（GitHub 累计）")
    for tag, assets in current["releases"].items():
        installs = assets.get("ScreenOff.dmg", 0)
        updates = assets.get("ScreenOff.zip", 0)
        checks = assets.get("appcast.xml", 0)
        line = f"  {tag}:  首装 DMG {installs}   更新 ZIP {updates}   检查 appcast {checks}"
        if previous and tag in previous["releases"]:
            before = previous["releases"][tag]
            delta = [
                f"{name} +{assets.get(name, 0) - before.get(name, 0)}"
                for name in ("ScreenOff.dmg", "ScreenOff.zip", "appcast.xml")
                if assets.get(name, 0) - before.get(name, 0) > 0
            ]
            if delta:
                line += f"   (较 {previous['at'][:10]}: {', '.join(delta)})"
        print(line)
    if not previous:
        print("  这是第一份快照，下次运行才能给出增量。")


def pull_log(host: str, key: str | None) -> list[str]:
    command = ["ssh"]
    if key:
        # 显式密钥时绕开 agent 与本机别名，别名可能被代理规则劫持到别的主机。
        command += ["-i", key, "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none"]
    command += ["-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
                host, f"tail -n 200000 {REMOTE_LOG}"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"ssh {host} 失败")
    return result.stdout.splitlines()


def report_log(lines: list[str], days: int) -> None:
    per_day: Counter[str] = Counter()
    downloads: Counter[str] = Counter()
    profiles: dict[str, Counter[str]] = defaultdict(Counter)
    profiled_requests = 0

    for line in lines:
        match = LOG_LINE.match(line)
        if not match:
            continue
        day = match.group("time")[:10]
        target = match.group("request").split(" ")
        if len(target) < 2:
            continue
        parts = urlsplit(target[1])
        if parts.path.endswith("appcast.xml"):
            per_day[day] += 1
            query = parse_qs(parts.query)
            if query:
                profiled_requests += 1
                for field in ("appVersion", "osVersion", "model", "lang", "ncpu", "ramMB"):
                    if field in query:
                        profiles[field][query[field][0]] += 1
        elif parts.path.endswith((".zip", ".dmg")) and match.group("status") == "200":
            downloads[parts.path.rsplit("/", 1)[-1]] += 1

    recent = sorted(per_day.items())[-days:]
    print("\n更新检查（US1 日志，≈ 日活跃安装数）")
    if not recent:
        print("  日志里还没有记录。确认 log_format 已安装且 nginx 已重载。")
        return
    width = max(len(str(count)) for _, count in recent)
    for day, count in recent:
        print(f"  {day}  {count:>{width}}  {'▊' * min(40, max(1, count * 40 // max(c for _, c in recent)))}")

    if downloads:
        print("\n镜像下载")
        for name, count in downloads.most_common():
            print(f"  {name}: {count}")

    if not profiles:
        print("\n系统画像：暂无。只有同意发送匿名信息的用户才会带上这些字段。")
        return
    print(f"\n系统画像（{profiled_requests} 次检查带有，其余用户未同意或使用旧版本）")
    labels = {
        "appVersion": "App 版本", "osVersion": "macOS", "model": "机型",
        "lang": "语言", "ncpu": "CPU 核心", "ramMB": "内存 MB",
    }
    for field, label in labels.items():
        if field not in profiles:
            continue
        top = profiles[field].most_common(6)
        rendered = "  ".join(f"{value}×{count}" for value, count in top)
        print(f"  {label}: {rendered}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Screen Off 使用情况汇总")
    parser.add_argument("--repo", default="imetn/ScreenOff")
    parser.add_argument("--host", help="更新服务器的 SSH 目标，如 root@203.0.113.10；省略则只看 GitHub")
    parser.add_argument("--ssh-key", help="SSH 私钥路径，避免本机 SSH 别名被代理规则劫持")
    parser.add_argument("--log-file", help="改为分析本地的一份日志副本")
    parser.add_argument("--days", type=int, default=14)
    args = parser.parse_args()

    try:
        releases = fetch_github(args.repo)
    except (urllib.error.URLError, RuntimeError, TimeoutError) as error:
        print(f"GitHub 数据获取失败：{error}", file=sys.stderr)
        return 1
    report_github(snapshot_github(releases))

    if args.log_file:
        report_log(Path(args.log_file).read_text().splitlines(), args.days)
    elif args.host:
        try:
            report_log(pull_log(args.host, args.ssh_key), args.days)
        except (RuntimeError, subprocess.TimeoutExpired, FileNotFoundError) as error:
            print(f"\n更新日志获取失败：{error}", file=sys.stderr)
            return 1
    else:
        print("\n提示：加 --host <ssh 主机> 可一并分析 US1 的更新日志。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
