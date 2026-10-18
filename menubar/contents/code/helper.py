#!/usr/bin/python3 -I
"""Data source for the Apple Menu widget. Prints JSON on stdout.

  helper.py recent   recent applications (KDE activity database) and documents
                     (activity database + recently-used.xbel)
  helper.py clear    hide everything listed so far (Clear Menu)
  helper.py info     hardware/OS summary for About This Computer
  helper.py user     the user's full name
"""
import configparser
import json
import math
import mimetypes
import os
import platform
import pwd
import socket
import sqlite3
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime
from urllib.parse import unquote

DB = os.path.expanduser('~/.local/share/kactivitymanagerd/resources/database')
XBEL = os.path.expanduser('~/.local/share/recently-used.xbel')
CLEARED = os.path.expanduser('~/.local/state/applemenu/cleared-at')
LIMIT = 10


def app_dirs():
    dirs = [os.environ.get('XDG_DATA_HOME', os.path.expanduser('~/.local/share'))]
    dirs += os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':')
    dirs += ['/var/lib/snapd/desktop', '/var/lib/flatpak/exports/share',
             os.path.expanduser('~/.local/share/flatpak/exports/share')]
    return [os.path.join(d, 'applications') for d in dirs]


def desktop_entry(desktop_id):
    for d in app_dirs():
        path = os.path.join(d, desktop_id)
        if not os.path.isfile(path):
            continue
        cp = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            cp.read(path, encoding='utf-8')
            entry = cp['Desktop Entry']
        except (configparser.Error, KeyError, UnicodeDecodeError):
            return None
        if entry.get('NoDisplay', 'false').lower() == 'true':
            return None
        return {'id': desktop_id, 'name': entry.get('Name', desktop_id), 'icon': entry.get('Icon', 'application-x-executable')}
    return None


def recent_rows(conn, pattern_sql):
    return conn.execute(
        'SELECT targettedResource, MAX(lastUpdate) AS t FROM ResourceScoreCache '
        f'WHERE {pattern_sql} GROUP BY targettedResource ORDER BY t DESC LIMIT 200').fetchall()


def cleared_at():
    try:
        return float(read(CLEARED))
    except ValueError:
        return 0.0


def xbel_files():
    """(path, unix time) for local files in recently-used.xbel."""
    try:
        root = ET.parse(XBEL).getroot()
    except (OSError, ET.ParseError):
        return []
    result = []
    for b in root.iter('bookmark'):
        href = b.get('href', '')
        if not href.startswith('file://'):
            continue
        stamp = b.get('visited') or b.get('modified') or b.get('added') or ''
        try:
            t = datetime.fromisoformat(stamp.replace('Z', '+00:00')).timestamp()
        except ValueError:
            t = 0.0
        result.append((unquote(href[len('file://'):]), t))
    return result


def recent():
    apps, candidates = [], []
    since = cleared_at()
    try:
        conn = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
        with conn:
            for res, t in recent_rows(conn, "targettedResource LIKE 'applications:%'"):
                if t <= since:
                    break
                entry = desktop_entry(res[len('applications:'):])
                if entry:
                    apps.append(entry)
                if len(apps) >= LIMIT:
                    break
            for res, t in recent_rows(conn, "targettedResource LIKE '/%' OR targettedResource LIKE 'file://%'"):
                candidates.append((unquote(res[len('file://'):]) if res.startswith('file://') else res, t))
    except sqlite3.Error:
        pass
    candidates += xbel_files()
    docs, seen = [], set()
    for path, t in sorted(candidates, key=lambda c: c[1], reverse=True):
        if t <= since or path in seen or not os.path.isfile(path):
            continue
        seen.add(path)
        mime = mimetypes.guess_type(path)[0] or 'text/plain'
        docs.append({'path': path, 'name': os.path.basename(path), 'icon': mime.replace('/', '-')})
        if len(docs) >= LIMIT:
            break
    return {'apps': apps, 'docs': docs}


def clear():
    """Hide everything used before now; the underlying history is kept."""
    os.makedirs(os.path.dirname(CLEARED), exist_ok=True)
    with open(CLEARED, 'w') as f:
        f.write(str(time.time()))
    return {'cleared': True}


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ''


def gpus():
    try:
        out = subprocess.run(['lspci'], capture_output=True, text=True, check=False).stdout
    except OSError:
        return []
    result = []
    for line in out.splitlines():
        if any(k in line for k in ('VGA compatible controller', '3D controller', 'Display controller')):
            name = line.split(': ', 1)[1]
            if '[' in name and ']' in name:
                name = name[name.index('[') + 1:name.rindex(']')]
            result.append(name.replace(' (rev', '').split(' (rev')[0])
    return result


def info():
    cpu = ''
    for line in read('/proc/cpuinfo').splitlines():
        if line.startswith('model name'):
            cpu = line.split(':', 1)[1].strip().replace('(R)', '').replace('(TM)', '')
            break
    mem_kb = 0
    for line in read('/proc/meminfo').splitlines():
        if line.startswith('MemTotal:'):
            mem_kb = int(line.split()[1])
    os_name = ''
    for line in read('/etc/os-release').splitlines():
        if line.startswith('PRETTY_NAME='):
            os_name = line.split('=', 1)[1].strip('"')
    return {
        'model': read('/sys/class/dmi/id/product_family') or read('/sys/class/dmi/id/product_name') or socket.gethostname(),
        'vendor': read('/sys/class/dmi/id/sys_vendor'),
        'cpu': cpu,
        'gpu': gpus(),
        # Installed RAM, not the usable amount the kernel reports.
        'memory': f'{math.ceil(mem_kb / 1024 / 1024 / 2) * 2} GB' if mem_kb else '',
        'os': os_name,
        'kernel': platform.release(),
        'hostname': socket.gethostname(),
    }


def user():
    entry = pwd.getpwuid(os.getuid())
    return {'name': entry.pw_gecos.split(',')[0] or entry.pw_name}


if __name__ == '__main__':
    commands = {'recent': recent, 'clear': clear, 'info': info, 'user': user}
    print(json.dumps(commands[sys.argv[1]]()))
