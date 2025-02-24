from setuptools import setup

setup(
    name="nixx",
    version="1.0.0",
    py_modules=["nixx"],
    entry_points={
        "console_scripts": [
            "nixx = nixx:main",
        ],
    },
)
