#!/usr/bin/env python3
"""
乔巴工具箱 - CI 平台补丁脚本（flutter create 后执行）
- Android: applicationId=com.qiaoba.toolbox、MainActivity.kt 覆盖、FileProvider 注册、androidx.core 依赖
- iOS: bundle id=com.qiaoba.toolbox、显示名=乔巴工具箱
双向容错：Android job 无 ios/ 目录时自动跳过 iOS 补丁，反之亦然。
"""
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

TOOL_DIR = os.path.join(ROOT, 'tool')


def patch_android():
    if not os.path.isdir('android'):
        print('[SKIP] android/ 不存在，跳过 Android 补丁')
        return

    # 1. applicationId / minSdk
    target = 'android/app/build.gradle.kts'
    if not os.path.exists(target):
        target = 'android/app/build.gradle'
    is_kts = target.endswith('.kts')
    with open(target, 'r', encoding='utf-8') as f:
        content = f.read()

    if is_kts:
        content = re.sub(r'applicationId\s*=\s*"[^"]*"',
                         'applicationId = "com.qiaoba.toolbox"', content)
        content = re.sub(r'minSdk\s*=\s*\d+', 'minSdk = 26', content)
    else:
        content = re.sub(r'applicationId\s+"[^"]*"',
                         'applicationId "com.qiaoba.toolbox"', content)
        content = re.sub(r'minSdkVersion\s+\d+', 'minSdkVersion 26', content)
    # abiFilters 只保留 arm64（用户是 64位 ARM 设备）
    if 'abiFilters' not in content:
        if is_kts:
            content = content.replace(
                'defaultConfig {',
                'defaultConfig {\n        ndk {\n            abiFilters += listOf("arm64-v8a")\n        }',
                1)
        else:
            content = content.replace(
                'defaultConfig {',
                "defaultConfig {\n        ndk { abiFilters \'arm64-v8a\' }",
                1)
        print('[OK] abiFilters → arm64-v8a only')

    with open(target, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'[OK] gradle patched: {target}')

    # 2. MainActivity.kt — 关键：包名必须与 applicationId 一致
    kt_src = os.path.join(TOOL_DIR, 'MainActivity.kt')
    # flutter create 会生成在 kotlin/<org 路径>/ 下；先删除旧的，再写入标准路径
    for root, dirs, files in os.walk('android/app/src/main/kotlin'):
        for name in files:
            if name == 'MainActivity.kt':
                old = os.path.join(root, name)
                os.remove(old)
                print(f'[CLEAN] removed old {old}')
    kt_dst = 'android/app/src/main/kotlin/com/qiaoba/toolbox/MainActivity.kt'
    os.makedirs(os.path.dirname(kt_dst), exist_ok=True)
    with open(kt_src, 'r', encoding='utf-8') as f:
        kt = f.read()
    with open(kt_dst, 'w', encoding='utf-8') as f:
        f.write(kt)
    print(f'[OK] MainActivity.kt written to {kt_dst}')

    # 2.1 关键修复：Manifest 中 activity 的 name 从 flutter create 默认值改为
    #     com.qiaoba.toolbox.MainActivity，与注入的 Kotlin 类全限定名一致
    # 2.2 说明：变量 m 尚未加载（Manifest 读取在下面），把 activity 修复挪到 3 步内
    # 3. AndroidManifest：label + INTERNET 权限 + activity 全限定名 + FileProvider
    manifest = 'android/app/src/main/AndroidManifest.xml'
    with open(manifest, 'r', encoding='utf-8') as f:
        m = f.read()
    if 'android:label="小助手"' not in m:
        m = re.sub(r'android:label="[^"]*"', 'android:label="小助手"', m, count=1)

    # 关键：注入 INTERNET 权限（flutter create 默认 Manifest 没有）
    # DNS 解析失败 Failed host lookup 的根因就是缺这个权限
    if 'android.permission.INTERNET' not in m:
        m = m.replace(
            '<application',
            '<uses-permission android:name="android.permission.INTERNET" />\n'
            '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />\n'
            '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n\n'
            '    <application',
            1)
        print('[OK] INTERNET + INSTALL_PACKAGES permissions injected')

    # 修复 activity 全限定名（避免运行时 ClassNotFoundException 闪退）
    if 'android:name=".MainActivity"' in m:
        m = m.replace('android:name=".MainActivity"',
                      'android:name="com.qiaoba.toolbox.MainActivity"')
        print('[OK] Manifest activity name → com.qiaoba.toolbox.MainActivity')
    elif 'com.qiaoba.qiaoba_toolbox.MainActivity' in m:
        m = m.replace('com.qiaoba.qiaoba_toolbox.MainActivity',
                      'com.qiaoba.toolbox.MainActivity')
        print('[OK] Manifest activity name → com.qiaoba.toolbox.MainActivity')

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
    print('[OK] AndroidManifest patched')

    # 4. file_paths.xml
    paths_src = os.path.join(TOOL_DIR, 'file_paths.xml')
    paths_dst = 'android/app/src/main/res/xml/file_paths.xml'
    os.makedirs(os.path.dirname(paths_dst), exist_ok=True)
    with open(paths_src, 'r', encoding='utf-8') as f:
        p = f.read()
    with open(paths_dst, 'w', encoding='utf-8') as f:
        f.write(p)
    print('[OK] file_paths.xml written')

    # 5. androidx.core 依赖
    with open(target, 'r', encoding='utf-8') as f:
        g = f.read()
    if 'androidx.core' not in g:
        if is_kts:
            dep = '\ndependencies {\n    implementation("androidx.core:core-ktx:1.13.1")\n}\n'
        else:
            dep = '\ndependencies {\n    implementation "androidx.core:core-ktx:1.13.1"\n}\n'
        g = g.rstrip() + dep
        with open(target, 'w', encoding='utf-8') as f:
            f.write(g)
        print('[OK] androidx.core dependency added')


def patch_ios():
    if not os.path.isdir('ios'):
        print('[SKIP] ios/ 不存在，跳过 iOS 补丁')
        return
    pbx = 'ios/Runner.xcodeproj/project.pbxproj'
    if os.path.exists(pbx):
        with open(pbx, 'r', encoding='utf-8') as f:
            c = f.read()
        c = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;',
                   'PRODUCT_BUNDLE_IDENTIFIER = com.qiaoba.toolbox;', c)
        c = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[^;]+;',
                   'IPHONEOS_DEPLOYMENT_TARGET = 13.0;', c)
        with open(pbx, 'w', encoding='utf-8') as f:
            f.write(c)
        print('[OK] iOS bundle id & deployment target 13.0 patched')
    plist = 'ios/Runner/Info.plist'
    if os.path.exists(plist):
        subprocess.run(['/usr/libexec/PlistBuddy', '-c',
                        'Set :CFBundleDisplayName 小助手', plist], capture_output=True)
        subprocess.run(['/usr/libexec/PlistBuddy', '-c',
                        'Set :MinimumOSVersion 13.0', plist], capture_output=True)
        print('[OK] iOS display name 小助手 & MinimumOSVersion 13.0 patched')


patch_android()
patch_ios()
print('All platform patches applied.')
