Copy the official macOS Python distribution into this directory.
The expected layout is:

EmbeddedPython
└── Python.framework
    └── Versions
        └── 3.9 -> 3.9.6

Place the entire `Python.framework` folder from `/Library/Frameworks`
so that `bin/python3` resides at:
`EarprintGUI.app/Contents/Resources/EmbeddedPython/Python.framework/Versions/3.9/bin/python3`.