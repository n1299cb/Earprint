# See NOTICE.md for license and attribution details.

"""Utility for preparing and validating HRIR capture folders.

When run normally it creates a capture directory, populates it with
placeholder sweep files for each expected recording and writes a README
listing the files.  With ``--verify`` it checks for missing or unexpected
recordings in the directory.
"""

import argparse
import os
import shutil
from typing import Optional

from constants import (
    SPEAKER_LAYOUTS,
    save_user_layout_preset,
    load_and_register_user_layouts,
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SWEEP = os.path.join(
    BASE_DIR,
    "data",
    "sweep-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav",
)


def select_layout(name: Optional[str]) -> tuple[str, list[list[str]]]:
    """Return layout name and groups, prompting user if needed."""
    layout_names = list(SPEAKER_LAYOUTS.keys())
    if name is None:
        print("🎧 Select speaker layout:")
        for i, lname in enumerate(layout_names, 1):
            print(f"{i}. {lname}")
        choice = input("\nEnter layout number: ")
        try:
            name = layout_names[int(choice) - 1]
        except (IndexError, ValueError):
            raise SystemExit("❌ Invalid selection.")
    if name not in SPEAKER_LAYOUTS:
        raise SystemExit(f"❌ Unknown layout '{name}'.")
    return name, SPEAKER_LAYOUTS[name]


def init_layout(layout_name: str, groups: list[list[str]], out_dir: str) -> None:
    """Create capture directory and placeholder files."""
    os.makedirs(out_dir, exist_ok=True)
    readme_path = os.path.join(out_dir, "README.md")
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(f"# HRIR Capture Layout: {layout_name}\n\n")
        f.write("## Expected Files:\n")
        for group in groups:
            filename = ",".join(group) + ".wav"
            f.write(f"- `{filename}` → {', '.join(group)}\n")
        f.write("\nMake sure each file contains properly labeled and measured IRs.\n")

    for group in groups:
        filename = ",".join(group) + ".wav"
        dst = os.path.join(out_dir, filename)
        if not os.path.exists(dst):
            shutil.copyfile(DEFAULT_SWEEP, dst)

    print(f"\n✅ Layout `{layout_name}` initialized at {out_dir}")
    print("💡 Placeholder sweep files written. Overwrite them with your recordings.\n")


def verify_layout(layout_name: str, groups: list[list[str]], out_dir: str) -> None:
    """Check that all expected recordings exist and list unexpected ones."""
    expected = {",".join(g) + ".wav" for g in groups}
    found = {f for f in os.listdir(out_dir) if f.lower().endswith(".wav")}
    missing = sorted(expected - found)
    extra = sorted(found - expected)

    print(f"Verifying layout `{layout_name}` in {out_dir}\n")
    if missing:
        print("❌ Missing recordings:")
        for m in missing:
            print(f"- {m}")
    else:
        print("✅ All expected files are present.")

    if extra:
        print("\n⚠️  Unexpected files:")
        for e in extra:
            print(f"- {e}")


def list_layouts() -> None:
    """Print available layout names."""
    print("Available layouts:\n")
    for name in SPEAKER_LAYOUTS:
        print(f"- {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare or verify capture folders")
    parser.add_argument("--layout", help="Layout name to use")
    parser.add_argument("--dir", default="data/test_capture", help="Target directory")
    parser.add_argument("--verify", action="store_true", help="Verify existing files")
    parser.add_argument("--save_preset", metavar="FILE", help="Write layout groups to JSON preset")
    parser.add_argument("--preset_file", help="JSON file with additional layouts")
    parser.add_argument("--list", action="store_true", help="List available layouts and exit")
    args = parser.parse_args()

    if args.preset_file:
        load_and_register_user_layouts(args.preset_file)

    if args.list:
        list_layouts()
        return

    layout_name, groups = select_layout(args.layout)

    if args.verify:
        verify_layout(layout_name, groups, args.dir)
    else:
        init_layout(layout_name, groups, args.dir)

    if args.save_preset:
        save_user_layout_preset(layout_name, groups, args.save_preset)


if __name__ == "__main__":
    main()
