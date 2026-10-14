"""Produce Android platform fields from a built APK; never publish/configure it."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import urllib.parse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True, type=pathlib.Path)
    parser.add_argument('--aapt', required=True, type=pathlib.Path)
    parser.add_argument('--url', required=True, help='HTTPS APK direct URL')
    parser.add_argument('--website', default='https://99chat.vip')
    parser.add_argument('--minimum', default='', help='Empty means optional update')
    parser.add_argument('--gray', type=int, default=100)
    parser.add_argument('--changelog', default='')
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    url = urllib.parse.urlparse(args.url)
    if url.scheme != 'https' or not url.hostname or url.username or url.fragment:
        parser.error('url must be an HTTPS APK URL without credentials or fragment')
    if not 0 <= args.gray <= 100:
        parser.error('gray must be 0..100')
    output = subprocess.check_output([str(args.aapt), 'dump', 'badging', str(args.apk)], text=True, encoding='utf-8')
    match = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", output)
    if not match or match[1] != 'chat.chat99.chatpro':
        parser.error('APK must be the chat.chat99.chatpro application')
    version = f'{match[3]}+{match[2]}'
    if not re.fullmatch(r'\d+\.\d+\.\d+\+[1-9]\d*', version):
        parser.error('APK requires a numeric versionName and positive versionCode')
    if args.minimum:
        if not re.fullmatch(r'\d+\.\d+\.\d+(\+[1-9]\d*)?', args.minimum):
            parser.error('minimum must be version or version+build')
        def parts(value):
            return tuple(int(x) for x in re.split(r'[.+]', value))
        if parts(args.minimum) > parts(version):
            parser.error('minimum cannot exceed APK version')
    size = args.apk.stat().st_size
    if not 0 < size <= 2147483648:
        parser.error('APK size must be 1..2147483648 bytes')
    digest = hashlib.sha256()
    with args.apk.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    manifest = dict(version=version, latestVersion=version, minVersion=args.minimum,
                    grayRatio=args.gray, changelog=args.changelog,
                    downloadLink=args.url, downloadURL=args.website,
                    packageSha256=digest.hexdigest(), packageSize=size,
                    versionCode=int(match[2]))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Wrote Android fields to {args.output}. No server settings changed.')


if __name__ == '__main__':
    main()
