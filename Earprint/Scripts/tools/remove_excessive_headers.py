import pathlib
import re

HEADER = "# See NOTICE.md for license and attribution details.\n"

keyword_re = re.compile(r"(earprint|impulcifer|blaring sound)", re.IGNORECASE)

for path in pathlib.Path('.').rglob('*.py'):
    if path.is_file() and path.parts[0] != 'tests' and path.parts[0] != '.git':
        lines = path.read_text().splitlines(keepends=True)
        if not lines:
            continue
        idx = 0
        if keyword_re.search(lines[0]):
            idx = 1
            # remove subsequent comment lines belonging to the header
            while idx < len(lines) and (lines[idx].startswith('#') or lines[idx].strip() == ''):
                idx += 1
            while idx < len(lines) and lines[idx].strip() == '':
                idx += 1
            lines = [HEADER, '\n'] + lines[idx:]
            path.write_text(''.join(lines))
            print(f"Updated {path}")