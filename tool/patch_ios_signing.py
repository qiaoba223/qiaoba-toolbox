#!/usr/bin/env python3
"""CI 专用：iOS pbxproj 注入禁签三件套"""
import os
import re

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

pbx = 'ios/Runner.xcodeproj/project.pbxproj'
with open(pbx, 'r', encoding='utf-8') as f:
    c = f.read()

if 'CODE_SIGNING_ALLOWED' not in c:
    c = re.sub(
        r'(buildSettings\s*=\s*\{)',
        r'''\1
                              CODE_SIGNING_ALLOWED = NO;
                              CODE_SIGNING_REQUIRED = NO;
                              CODE_SIGN_IDENTITY = "";''',
        c)
    with open(pbx, 'w', encoding='utf-8') as f:
        f.write(c)
    print('[OK] pbxproj CODE_SIGNING patched')
else:
    print('[SKIP] already patched')
