#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cria o module.xml de um plugin da suíte.
   python3 tools/new_module.py Pasta Id "Nome" "Descrição" """
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def write(folder, mid, name, desc):
    d = os.path.join(ROOT, "plugins", folder)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "module.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write('''<?xml version="1.0" encoding="UTF-8"?>
<module sdkVersion="3.7b">
    <!-- O id identifica o plugin globalmente e NÃO deve mudar depois de publicado. -->
    <id>%s</id>
    <version>1.0.0</version>
    <info lang="pt-BR">
        <name>%s</name>
        <description>%s</description>
        <author>Scene Suite</author>
        <site></site>
        <contact></contact>
    </info>
</module>
''' % (mid, name, desc))


if __name__ == "__main__":
    write(*sys.argv[1:5])
