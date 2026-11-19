"""Builds the release zip and uploads it to CurseForge.

Used by .github/workflows/release.yml whenever main is pushed:
  1. Reads the version from RankWarden.toc (and checks RankWarden.lua matches).
  2. Skips if tag v<version> already exists — so only a version bump publishes.
  3. Takes that version's notes from CHANGELOG.md ("## <version>" section).
  4. Builds dist/RankWarden-<version>.zip (RankWarden/ at the root, forward slashes).
  5. Uploads it to CurseForge for the game version in CF_GAME_VERSION.

Environment:
  CF_API_KEY        CurseForge API token (repository secret). Required to upload.
  CF_PROJECT_ID     defaults to the X-Curse-Project-ID in the TOC.
  CF_GAME_VERSION   CurseForge game version name, default "1.60.1" (WoW: Forever).
  CF_RELEASE_TYPE   release | beta | alpha (default release).
  DRY_RUN=1         build and print, but don't upload.

Writes version/tag/zip/notes to $GITHUB_OUTPUT when running in Actions.
"""

import json
import os
import re
import subprocess
import sys
import urllib.request
import uuid
import zipfile

ADDON = "RankWarden"
API = "https://wow.curseforge.com/api"

# Never shipped in the zip (dev tooling, tests, sources of generated data).
EXCLUDE_DIRS = (".github/", ".vscode/", "tests/", "tools/", "media/", "dist/")
EXCLUDE_FILES = {
    "export.ps1", "run.ps1", ".luacheckrc", ".busted", ".luacov", ".stylua.toml",
    ".styluaignore", ".gitignore", ".pkgmeta", "CHANGELOG.md", "CONTRIBUTING.md",
}


def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)


def toc_field(toc, field):
    m = re.search(rf"^## {re.escape(field)}:\s*(.+?)\s*$", toc, re.M)
    return m.group(1) if m else None


def read_version():
    toc = open(f"{ADDON}.toc", encoding="utf-8").read()
    version = toc_field(toc, "Version")
    if not version:
        fail("No '## Version:' in the TOC.")
    core = open(f"{ADDON}.lua", encoding="utf-8").read()
    m = re.search(r'local ADDON_VERSION = "([^"]+)"', core)
    if not m or m.group(1) != version:
        fail(f"Version mismatch: TOC says {version}, {ADDON}.lua says {m and m.group(1)}.")
    return version, toc_field(toc, "X-Curse-Project-ID")


def tag_exists(tag):
    out = subprocess.run(["git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}"],
                         capture_output=True, text=True, check=False).stdout
    local = subprocess.run(["git", "tag", "-l", tag], capture_output=True, text=True, check=False).stdout
    return bool(out.strip() or local.strip())


def changelog_section(version):
    text = open("CHANGELOG.md", encoding="utf-8").read()
    m = re.search(rf"^## {re.escape(version)}\b.*?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m or not m.group(1).strip():
        fail(f"CHANGELOG.md has no '## {version}' section.")
    return m.group(1).strip()


def build_zip(version):
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split("\n")
    os.makedirs("dist", exist_ok=True)
    path = f"dist/{ADDON}-{version}.zip"
    count = 0
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            if not f or f.startswith(EXCLUDE_DIRS) or f in EXCLUDE_FILES:
                continue
            z.write(f, f"{ADDON}/{f}")
            count += 1
    print(f"Built {path} ({count} files)")
    return path


def api(path, token, data=None, content_type=None):
    req = urllib.request.Request(API + path, data=data, headers={"X-Api-Token": token})
    if content_type:
        req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def game_version_id(token, name):
    versions = api("/game/versions", token)
    ids = [v["id"] for v in versions if v.get("name") == name]
    if not ids:
        close = sorted({v["name"] for v in versions if v.get("name", "").startswith(name.split(".")[0] + ".")})[-15:]
        fail(f"CurseForge has no game version named {name!r}. Recent similar: {close}")
    return ids


def upload(token, project, zip_path, version, notes, game_ids, release_type):
    metadata = {
        "changelog": notes,
        "changelogType": "markdown",
        "displayName": f"{ADDON} {version}",
        "gameVersions": game_ids,
        "releaseType": release_type,
    }
    boundary = uuid.uuid4().hex
    with open(zip_path, "rb") as fh:
        payload = fh.read()
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n".encode()
        + json.dumps(metadata).encode()
        + f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
          f"filename=\"{os.path.basename(zip_path)}\"\r\nContent-Type: application/zip\r\n\r\n".encode()
        + payload
        + f"\r\n--{boundary}--\r\n".encode()
    )
    result = api(f"/projects/{project}/upload-file", token, body, f"multipart/form-data; boundary={boundary}")
    print(f"Uploaded to CurseForge: file id {result.get('id')}")


def output(**kv):
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as f:
        for k, v in kv.items():
            if "\n" in str(v):
                f.write(f"{k}<<EOF\n{v}\nEOF\n")
            else:
                f.write(f"{k}={v}\n")


def main():
    version, toc_project = read_version()
    tag = f"v{version}"
    if tag_exists(tag):
        print(f"{tag} is already released — bump '## Version' in {ADDON}.toc to publish a new one.")
        output(release="false")
        return

    notes = changelog_section(version)
    zip_path = build_zip(version)
    output(release="true", version=version, tag=tag, zip=zip_path, notes=notes)

    if os.environ.get("DRY_RUN") == "1":
        print("DRY_RUN=1: not uploading.\n" + notes)
        return

    token = os.environ.get("CF_API_KEY")
    if not token:
        # Not an error: nothing is tagged, so the next run (or a manual re-run) publishes it.
        print("::warning::CF_API_KEY secret is not set, so nothing was uploaded. Create a CurseForge API "
              "token, run `gh secret set CF_API_KEY --repo highnet/RankWarden`, then re-run the Release workflow.")
        output(release="false")
        return
    project = os.environ.get("CF_PROJECT_ID") or toc_project
    if not project:
        fail("No CurseForge project ID (X-Curse-Project-ID in the TOC or CF_PROJECT_ID).")
    game_ids = game_version_id(token, os.environ.get("CF_GAME_VERSION", "1.60.1"))
    upload(token, project, zip_path, version, notes, game_ids, os.environ.get("CF_RELEASE_TYPE", "release"))


if __name__ == "__main__":
    main()
