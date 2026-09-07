#!/usr/bin/env python3
"""CI 专用：注入 Android 原生安装器平台通道"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
TOOL_DIR = os.path.join(ROOT, 'tool')

# 1. MainActivity.kt
kt_src = os.path.join(TOOL_DIR, 'MainActivity.kt')
kt_dst = 'android/app/src/main/kotlin/com/qiaoba/toolbox/MainActivity.kt'
os.makedirs(os.path.dirname(kt_dst), exist_ok=True)
with open(kt_src, 'r', encoding='utf-8') as f:
    kt = f.read()
with open(kt_dst, 'w', encoding='utf-8') as f:
    f.write(kt)
print(f'[OK] MainActivity.kt → {kt_dst}')

# 2. 删除 flutter create 生成的旧 MainActivity
for root, dirs, files in os.walk('android/app/src/main/kotlin'):
    for name in files:
        if name == 'MainActivity.kt':
            p = os.path.join(root, name)
            if os.path.normpath(p) != os.path.normpath(kt_dst):
                os.remove(p)
                print(f'[CLEAN] removed old {p}')

# 3. file_paths.xml
paths_dst = 'android/app/src/main/res/xml/file_paths.xml'
os.makedirs(os.path.dirname(paths_dst), exist_ok=True)
with open(os.path.join(TOOL_DIR, 'file_paths.xml'), 'r', encoding='utf-8') as f:
    paths = f.read()
with open(paths_dst, 'w', encoding='utf-8') as f:
    f.write(paths)
print('[OK] file_paths.xml')

# 4. AndroidManifest FileProvider
manifest = 'android/app/src/main/AndroidManifest.xml'
with open(manifest, 'r', encoding='utf-8') as f:
    m = f.read()
if 'androidx.core.content.FileProvider' not in m:
    provider = '''
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
'''
    if '</application>' in m:
        m = m.replace('</application>', provider + '    </application>')
        with open(manifest, 'w', encoding='utf-8') as f:
            f.write(m)
        print('[OK] FileProvider registered')
else:
    print('[SKIP] FileProvider already present')

# 5. androidx.core 依赖
gradle_target = 'android/app/build.gradle.kts'
with open(gradle_target, 'r', encoding='utf-8') as f:
    g = f.read()
if 'androidx.core' not in g:
    dep = '\ndependencies {\n    implementation("androidx.core:core-ktx:1.13.1")\n}\n'
    g = g.rstrip() + dep
    with open(gradle_target, 'w', encoding='utf-8') as f:
        f.write(g)
    print('[OK] androidx.core added')
