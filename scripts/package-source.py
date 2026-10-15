"""Package the reviewed macOS source inventory, including uncommitted files."""

from pathlib import Path
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parent.parent
ROOT_FILES = {
    ".gitignore", ".gitattributes", "Package.swift", "README.md", "LICENSE",
    "THIRD_PARTY_NOTICES.md", "CONTRIBUTING.md", "PRIVACY.md", "SECURITY.md",
    "CHANGELOG.md",
}
SOURCE_DIRS = {".github", "Docs", "Resources", "Sources", "Tests", "Vendor"}
SCRIPTS = {
    "build-app.sh", "build-taglib.sh", "build-dmg.sh", "check.sh", "make-icon.swift",
    "package-source.sh", "package-source.py",
}
PRIVATE_SUFFIXES = {".p12", ".pfx", ".key", ".pem", ".jks", ".keystore", ".mobileprovision"}
EXCLUDED_PARTS = {".git", ".build", "build", ".swiftpm", ".android-tools", "android", "__pycache__", "xcuserdata"}


def main():
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT, check=True, stdout=subprocess.PIPE,
    )
    names = sorted(set(result.stdout.decode("utf-8").rstrip("\0").split("\0")))
    rejected = []
    for name in names:
        path = Path(name)
        allowed = name in ROOT_FILES or path.parts[0] in SOURCE_DIRS
        allowed |= len(path.parts) == 2 and path.parts[0] == "scripts" and path.name in SCRIPTS
        private = path.suffix.lower() in PRIVATE_SUFFIXES or path.name.startswith(".env")
        unsafe = path.is_absolute() or ".." in path.parts or bool(set(path.parts) & EXCLUDED_PARTS)
        source = ROOT / path
        if not allowed or private or unsafe or not source.is_file() or source.is_symlink():
            rejected.append(name)
        elif not source.resolve().is_relative_to(ROOT):
            rejected.append(name)
    required = ROOT_FILES | {"scripts/" + name for name in SCRIPTS} | {
        "Vendor/taglib-2.2.1/COPYING.MPL", "Vendor/taglib-2.2.1/3rdparty/utfcpp/LICENSE",
        "Resources/Info.plist",
    }
    missing = sorted(required - set(names))
    if rejected or missing:
        raise SystemExit(
            "Source package refused. Review these paths before packaging.\n"
            + "".join("Unexpected or unsafe: " + name + "\n" for name in rejected)
            + "".join("Missing required file: " + name + "\n" for name in missing)
        )
    output = ROOT / "build"
    output.mkdir(exist_ok=True)
    archive = output / "Still-Music-macOS-source.zip"
    manifest = output / "Still-Music-macOS-source-files.txt"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for name in names:
            package.write(ROOT / name, "StillMusic-macOS/" + name)
    manifest.write_text("\n".join(names) + "\n", encoding="utf-8")
    print(f"Packaged {len(names)} files: {archive}\nReview inventory: {manifest}")


if __name__ == "__main__":
    main()
