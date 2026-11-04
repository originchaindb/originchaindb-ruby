"""Install a built candidate into a temporary application. No registry uploads."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts"


def run(command, cwd, env=None):
    subprocess.run([str(value) for value in command], cwd=cwd, env=env, check=True)


with tempfile.TemporaryDirectory(prefix="originchaindb-install-") as temporary:
    app = Path(temporary)
    artifact = next(ARTIFACTS.glob("*.gem"))
    ruby = shutil.which("ruby") or "ruby"
    gem = Path(ruby).parent / "gem"
    run(
        [
            ruby,
            gem,
            "install",
            artifact,
            "--install-dir",
            app / "gems",
            "--no-document",
        ],
        app,
    )
    run(
        [
            ruby,
            "-e",
            "require 'originchaindb'; db=OriginChainDB::Client.new(url:'https://example.invalid',token:'test'); %i[write_batches pages scan].each{|name|raise name.to_s unless db.rows.respond_to?(name)}; db.close",
        ],
        app,
        dict(
            os.environ,
            GEM_HOME=str(app / "gems"),
            GEM_PATH=str(app / "gems") + os.pathsep + os.environ.get("GEM_PATH", ""),
        ),
    )
print("Fresh package application passed: " + "ruby")
