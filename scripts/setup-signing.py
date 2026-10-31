#!/usr/bin/env python3
"""Create and reuse a local, non-extractable code-signing identity."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

SIGNING_DIR = Path.home() / 'Library/Application Support/TVVTNative/Signing'
KEYCHAIN = Path.home() / 'Library/Keychains/login.keychain-db'
NAME = 'TVVTNative Local Code Signing'

def run(args, **kwargs):
    result = subprocess.run(args, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} 操作失败（退出码 {result.returncode}）')
    return result

def setup():
    SIGNING_DIR.mkdir(parents=True, exist_ok=True)
    SIGNING_DIR.chmod(0o700)
    identity = SIGNING_DIR / 'identity.sha1'
    pending = SIGNING_DIR / 'identity.pending.sha1'
    public_cert = SIGNING_DIR / 'certificate.pem'
    if identity.exists():
        identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
        if identity.read_text().strip() in identities:
            print('固定签名身份已就绪，无需重新创建。')
            return
        raise RuntimeError('固定证书不可用，请先在钥匙串中解锁或恢复原证书；不会自动更换身份。')
    if not pending.exists():
        openssl = shutil.which('openssl')
        if not openssl:
            raise RuntimeError('需要 OpenSSL 3 或更新版本。')
        with tempfile.TemporaryDirectory(prefix='tvvt-signing-') as folder:
            temp = Path(folder)
            key, cert, archive = (temp / name for name in ['key.pem', 'cert.pem', 'identity.p12'])
            config = temp / 'openssl.cnf'
            config.write_text('[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=extensions\n'
                              '[dn]\nCN=' + NAME + '\n[extensions]\nbasicConstraints=critical,CA:FALSE\n'
                              'keyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n')
            run([openssl, 'req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256', '-days', '3650',
                 '-config', str(config), '-keyout', str(key), '-out', str(cert)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            key.chmod(0o600)
            password = secrets.token_urlsafe(32)
            env = os.environ.copy()
            env['TVVT_TEMP_P12_PASSWORD'] = password
            run([openssl, 'pkcs12', '-export', '-legacy', '-inkey', str(key), '-in', str(cert),
                 '-name', NAME, '-out', str(archive), '-passout', 'env:TVVT_TEMP_P12_PASSWORD'], env=env)
            run(['security', 'import', str(archive), '-k', str(KEYCHAIN), '-f', 'pkcs12', '-P', password,
                 '-x', '-T', '/usr/bin/codesign'], stdout=subprocess.DEVNULL)
            public_cert.write_bytes(cert.read_bytes())
            public_cert.chmod(0o600)
            fingerprint = subprocess.check_output([openssl, 'x509', '-in', str(cert), '-noout', '-fingerprint', '-sha1'], text=True)
            pending.write_text(fingerprint.strip().split('=', 1)[1].replace(':', '') + '\n')
    existing = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    if pending.read_text().strip() not in existing:
        print('正在请求用户级代码签名信任；如系统提示，请由本机用户完成解锁。', flush=True)
        run(['security', 'add-trusted-cert', '-r', 'trustRoot', '-p', 'codeSign', '-k', str(KEYCHAIN), str(public_cert)])
    run(['security', 'verify-cert', '-L', '-c', str(public_cert), '-p', 'codeSign'])
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    if pending.read_text().strip() not in identities:
        raise RuntimeError('证书尚未成为可用签名身份；保留待完成状态，不退回临时签名。')
    pending.replace(identity)
    print('固定签名身份已保存；后续构建复用同一证书。')

if __name__ == '__main__':
    setup()
