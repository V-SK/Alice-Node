# -*- mode: python ; coding: utf-8 -*-
a = Analysis(
    ['alice_node.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('core/', 'core/'),
    ],
    hiddenimports=[
        'core.model',
        'core.compression',
        'core.secure_wallet',
        'substrate_interface',
        'mnemonic',
        'cryptography',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='alice-miner-core',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
)
