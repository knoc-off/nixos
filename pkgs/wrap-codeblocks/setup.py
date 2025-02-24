# setup.py
from setuptools import setup

setup(
    name="wrap-codeblocks",
    version="1.0.0",
    py_modules=["wrap_codeblocks"],  # or the name of your script file without the .py
    entry_points={
        "console_scripts": [
            "wrap-codeblocks = wrap_codeblocks:main",
        ],
    },
)
