from setuptools import setup

setup(
    name='vim-ai-replicate-bridge',
    version='0.1.0',
    py_modules=['vim_ai_replicate_bridge'],
    install_requires=[
        'Flask',
        'replicate',
    ],
    entry_points={
        'console_scripts': [
            'vim_ai_replicate_bridge=vim_ai_replicate_bridge:main',
        ],
    },
)
