#!/usr/bin/env python3
"""Run the real iOS volume classes in an isolated simulator test application."""
import argparse
import json
import pathlib
import plistlib
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
BUNDLE = 'local.99chat.volume-session-smoke'


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('simulator', help='UDID of an already booted simulator')
    args = parser.parse_args()
    config = (ROOT / 'ios/Flutter/Generated.xcconfig').read_text().splitlines()
    flutter = pathlib.Path(next(line.split('=', 1)[1] for line in config if line.startswith('FLUTTER_ROOT=')))
    framework = flutter / 'bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator'
    build = ROOT / '.temp/volume-session-smoke'
    app = build / 'VolumeSmoke.app'
    app.mkdir(parents=True, exist_ok=True)
    info = dict(CFBundleIdentifier=BUNDLE, CFBundleExecutable='VolumeSmoke', CFBundleName='VolumeSmoke',
                CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0',
                MinimumOSVersion='15.0', UIDeviceFamily=[1, 2], UILaunchScreen={},
                UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False,
                    UISceneConfigurations=dict(UIWindowSceneSessionRoleApplication=[dict(
                        UISceneConfigurationName='smoke', UISceneDelegateClassName='VolumeSmoke.VolumeSmokeScene')])))
    with (app / 'Info.plist').open('wb') as stream:
        plistlib.dump(info, stream)
    (app / 'Frameworks').mkdir(exist_ok=True)
    if not (app / 'Frameworks/Flutter.framework').exists():
        shutil.copytree(framework / 'Flutter.framework', app / 'Frameworks/Flutter.framework', symlinks=True)
    sources = sorted((ROOT / 'local_plugin/volume_controller/ios/volume_controller/Sources/volume_controller').glob('*.swift'))
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-module-name', 'VolumeSmoke', '-swift-version', '5',
        '-target', 'arm64-apple-ios15.0-simulator', '-sdk', run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'),
        '-F', str(framework), '-framework', 'Flutter', '-framework', 'UIKit',
        '-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks',
        str(ROOT / 'ios/tests/Volume/VolumeSessionSmoke.swift'), *map(str, sources), '-o', str(app / 'VolumeSmoke')], check=True)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    subprocess.run(['xcrun', 'simctl', 'install', args.simulator, str(app)], check=True)
    try:
        subprocess.run(['xcrun', 'simctl', 'launch', args.simulator, BUNDLE], check=True)
        data = pathlib.Path(run('xcrun', 'simctl', 'get_app_container', args.simulator, BUNDLE, 'data'))
        report_file = data / 'Documents/volume-smoke.json'
        for _ in range(100):
            if report_file.exists():
                break
            time.sleep(0.2)
        report = json.loads(report_file.read_text())
        (build / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
        if not report['passed']:
            raise SystemExit(1)
    finally:
        subprocess.run(['xcrun', 'simctl', 'terminate', args.simulator, BUNDLE], check=False)
        subprocess.run(['xcrun', 'simctl', 'uninstall', args.simulator, BUNDLE], check=False)


if __name__ == '__main__':
    main()
