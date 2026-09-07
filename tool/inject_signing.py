#!/usr/bin/env python3
"""CI 专用：注入 Android 签名配置到 build.gradle.kts"""
import os
import re

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

target = 'android/app/build.gradle.kts'
with open(target, 'r', encoding='utf-8') as f:
    c = f.read()

if 'signingConfigs' not in c:
    signing = '''    signingConfigs {
        create("release") {
            val ksFile = file("qiaoba.keystore")
            if (ksFile.exists()) {
                storeFile = ksFile
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
                keyAlias = System.getenv("KEYSTORE_ALIAS") ?: ""
                keyPassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            }
        }
    }

'''
    c = re.sub(r'(    buildTypes\s*\{)', signing + r'\1', c, count=1)
    c = c.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = if (file("qiaoba.keystore").exists()) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")')
    with open(target, 'w', encoding='utf-8') as f:
        f.write(c)
    print('[OK] signing config injected')
else:
    print('[SKIP] signing already present')
