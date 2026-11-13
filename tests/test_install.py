import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import tempfile
import termios
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'install.sh'
GIT = shutil.which('git')
NODE = shutil.which('node')
PYTHON = shutil.which('python3')
FAKE_TOKEN = 'github_pat_TEST_ONLY_NOT_A_CREDENTIAL'


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.trace = self.root / 'trace.jsonl'
        self.source = self.root / 'fixture'
        self.source.mkdir()
        self.run_git('init', '-q', str(self.source))
        self.run_git('-C', str(self.source), 'config', 'user.email', 'fixture@example.test')
        self.run_git('-C', str(self.source), 'config', 'user.name', 'Test fixture')
        (self.source / 'setup.sh').write_text('''#!/usr/bin/env bash
# --bootstrap-commit= contract fixture
python3 - "$@" <<'PY'
import json, os, sys
from pathlib import Path
Path(os.environ['SETUP_RESULT']).write_text(json.dumps({'args':sys.argv[1:], 'has_token':bool(os.getenv('GITHUB_TOKEN'))}))
PY
exit "${SETUP_RC:-0}"
''')
        ops = self.source / 'containers/app-system/ops'
        ops.mkdir(parents=True)
        (ops / 'provision-environment.cjs').write_text('''
const prefixes=['MC','PROJECTS','KNOWLEDGE_SEARCH'];
module.exports={publicKeys:[...prefixes.flatMap(p=>[`${p}_ACCESS_TEAM_DOMAIN`,`${p}_ACCESS_AUDIENCE`,`${p}_PUBLIC_ORIGIN`]),'CRM_ACCESS_AUDIENCE'],validateFreshIdentity(v){
if(v.MC_BOOTSTRAP_OWNER_EMAIL!=='owner@example.test')throw Error('owner invalid');
if(!v.CRM_ACCESS_AUDIENCE)throw Error('audience missing');
}};
''')
        self.run_git('-C', str(self.source), 'add', '.')
        self.run_git('-C', str(self.source), 'commit', '-qm', 'fixture')
        self.run_git('-C', str(self.source), 'tag', 'v0.26.1')
        self.commit = self.run_git('-C', str(self.source), 'rev-parse', 'HEAD').strip()
        wrapper = f'''#!{PYTHON}
import json, os, pathlib, subprocess, sys, time
tool=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['TRACE'],'a') as f:f.write(json.dumps({{'tool':tool,'args':args,'has_token':bool(os.getenv('GITHUB_TOKEN'))}})+'\\n')
if tool=='uname':print('Darwin');sys.exit(0)
if tool=='id':print('501');sys.exit(0)
if tool=='docker':sys.exit(int(os.getenv('DOCKER_RC','0')))
if tool=='node':os.execv({NODE!r},[{NODE!r},*args])
if 'fetch' in args:
 if os.getenv('FETCH_SLEEP'):time.sleep(60)
 if os.getenv('FETCH_FAIL'):sys.exit(128)
 args[args.index('origin')]=os.environ['FIXTURE']
os.execv({GIT!r},[{GIT!r},*args])
'''
        for name in ['git', 'docker', 'node', 'uname', 'id']:
            file = self.bin / name
            file.write_text(wrapper)
            file.chmod(0o700)
        self.target = self.root / 'platform/instances/prod'
        self.env = {**os.environ, 'PATH': f'{self.bin}:{os.environ["PATH"]}',
                    'VB_ROOT': str(self.root / 'platform'), 'TRACE': str(self.trace),
                    'FIXTURE': str(self.source), 'SETUP_RESULT': str(self.root / 'result.json'),
                    'GITHUB_TOKEN': FAKE_TOKEN}
        self.args = ['--owner-email=owner@example.test']
        for prefix in ['MC', 'PROJECTS', 'KNOWLEDGE_SEARCH']:
            self.args += [f'--system-env={prefix}_ACCESS_TEAM_DOMAIN=fixture.cloudflareaccess.com',
                          f'--system-env={prefix}_ACCESS_AUDIENCE=fixture',
                          f'--system-env={prefix}_PUBLIC_ORIGIN=https://fixture.example.test']
        self.args += ['--system-env=CRM_ACCESS_AUDIENCE=fixture']

    def run_git(self, *args):
        return subprocess.check_output([GIT, *args], text=True, stderr=subprocess.DEVNULL)

    def invoke(self, extra=(), tty=True, confirmation='INSTALL', env=None, interrupt=False):
        command = ['/bin/bash', str(SCRIPT), *self.args, *extra]
        environment = {**self.env, **(env or {})}
        if not tty:
            result = subprocess.run(command, env=environment, capture_output=True, text=True,
                                    start_new_session=True, timeout=15)
            return result.returncode, result.stdout + result.stderr
        master, slave = pty.openpty()
        def terminal():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        process = subprocess.Popen(command, env=environment, stdin=slave, stdout=slave,
                                   stderr=slave, preexec_fn=terminal)
        os.close(slave)
        output, sent, token_sent, killed = b'', False, False, False
        deadline = time.monotonic() + 20
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try: chunk = os.read(master, 65536)
                    except OSError: break
                    if not chunk: break
                    output += chunk
                if not sent and b'Type INSTALL to continue: ' in output:
                    os.write(master, (confirmation + '\n').encode())
                    sent = True
                if not token_sent and b'GitHub token (hidden): ' in output:
                    time.sleep(.05)
                    os.write(master, (FAKE_TOKEN + '\n').encode())
                    token_sent = True
                if interrupt and not killed and b'Fetching platform source...' in output:
                    time.sleep(.2)
                    os.killpg(process.pid, signal.SIGTERM)
                    killed = True
                if process.poll() is not None: break
            if process.poll() is None:
                process.wait(timeout=2)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            os.close(master)
        decoded = output.decode(errors='replace')
        self.assertNotIn('An interactive terminal is required', decoded, 'PTY test needs terminal access')
        return process.returncode, decoded

    def trace_entries(self):
        return [json.loads(x) for x in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def assert_clean(self):
        self.assertEqual(list((self.root / 'platform/instances').glob('.bootstrap.*')), [])

    def test_fresh_handoff_exact_commit_no_token_leak(self):
        rc, output = self.invoke()
        self.assertEqual(rc, 0, output)
        result = json.loads((self.root / 'result.json').read_text())
        self.assertIn(f'--bootstrap-commit={self.commit}', result['args'])
        self.assertIn('--initialize-fresh-app-system', result['args'])
        self.assertFalse(result['has_token'])
        self.assertNotIn(FAKE_TOKEN, output)
        self.assertNotIn(FAKE_TOKEN, self.trace.read_text())
        self.assertNotIn(FAKE_TOKEN, (self.target / '.git/config').read_text())
        self.assertEqual(self.run_git('-C', str(self.target), 'rev-parse', 'HEAD').strip(), self.commit)
        token_children = [x for x in self.trace_entries() if x['has_token']]
        self.assertEqual(len(token_children), 1)
        self.assertEqual(token_children[0]['tool'], 'git')
        self.assertIn('fetch', token_children[0]['args'])
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o700)
        self.assert_clean()

    def test_check_is_read_only_without_tty(self):
        rc, output = self.invoke(['--check'], tty=False)
        self.assertEqual(rc, 0, output)
        self.assertFalse((self.root / 'platform').exists())
        self.assertFalse(any('fetch' in x['args'] for x in self.trace_entries()))

    def test_prompt_token_is_not_echoed(self):
        rc, output = self.invoke(env={'GITHUB_TOKEN': ''})
        self.assertEqual(rc, 0, output)
        self.assertIn('GitHub token (hidden)', output)
        self.assertNotIn(FAKE_TOKEN, output)

    def test_credential_helper_is_scoped_to_repository(self):
        rc, output = self.invoke()
        self.assertEqual(rc, 0, output)
        fetch = next(x for x in self.trace_entries() if 'fetch' in x['args'])
        helper = next(arg.removeprefix('credential.helper=!') for arg in fetch['args']
                      if arg.startswith('credential.helper=!'))
        for host, path, allowed in [('github.com', 'victorblanco-tech/ai-assistant.git', True),
                                    ('other.example', 'victorblanco-tech/ai-assistant.git', False),
                                    ('github.com', 'other/repo.git', False)]:
            result = subprocess.run(['/bin/bash', '-c', helper + ' get'],
                                    input=f'protocol=https\nhost={host}\npath={path}\n\n',
                                    capture_output=True, text=True, env={'GITHUB_TOKEN': FAKE_TOKEN})
            self.assertEqual(FAKE_TOKEN in result.stdout, allowed)

    def test_no_tty_fails_before_clone(self):
        rc, output = self.invoke(tty=False)
        self.assertNotEqual(rc, 0)
        self.assertIn('interactive terminal', output)
        self.assertFalse((self.root / 'platform').exists())

    def test_invalid_destinations(self):
        for arg in ['../escape', '/tmp/escape', '--unknown', '--ref=main']:
            with self.subTest(arg=arg):
                rc, _ = self.invoke([arg], tty=False)
                self.assertNotEqual(rc, 0)
        self.assertFalse((self.root / 'platform').exists())

    def test_existing_instance_unchanged(self):
        self.target.mkdir(parents=True)
        marker = self.target / 'keep'
        marker.write_text('untouched')
        rc, output = self.invoke(tty=False)
        self.assertNotEqual(rc, 0)
        self.assertIn('already exists', output)
        self.assertEqual(marker.read_text(), 'untouched')

    def test_symlink_parent_refused(self):
        (self.root / 'platform').symlink_to(self.source, target_is_directory=True)
        rc, output = self.invoke(tty=False)
        self.assertNotEqual(rc, 0)
        self.assertIn('Symlinked', output)
        self.assertFalse((self.source / 'instances').exists())

    def test_cancel_before_mutation(self):
        rc, _ = self.invoke(confirmation='NO')
        self.assertNotEqual(rc, 0)
        self.assertFalse((self.root / 'platform').exists())

    def test_auth_failure_cleans_partial_source(self):
        rc, output = self.invoke(env={'FETCH_FAIL': '1'})
        self.assertNotEqual(rc, 0)
        self.assertIn('Source access failed', output)
        self.assertFalse(self.target.exists())
        self.assert_clean()

    def test_interruption_cleans_partial_source(self):
        rc, _ = self.invoke(env={'FETCH_SLEEP': '1'}, interrupt=True)
        self.assertNotEqual(rc, 0)
        self.assertFalse(self.target.exists())
        self.assert_clean()

    def test_setup_failure_preserves_checkout_and_exit_code(self):
        rc, output = self.invoke(env={'SETUP_RC': '42'})
        self.assertEqual(rc, 42, output)
        self.assertTrue((self.target / 'setup.sh').is_file())
        self.assert_clean()

    def test_bad_identity_does_not_publish_target(self):
        rc, _ = self.invoke(['--owner-email=invalid'])
        self.assertNotEqual(rc, 0)
        self.assertFalse(self.target.exists())
        self.assert_clean()

    def test_duplicate_or_secret_setting_refused(self):
        for value in ['MC_ACCESS_AUDIENCE=duplicate', 'OPENAI_API_KEY=not-a-key']:
            with self.subTest(value=value):
                rc, _ = self.invoke([f'--system-env={value}'])
                self.assertNotEqual(rc, 0)
                self.assertFalse(self.target.exists())
                self.assert_clean()

    def test_missing_release(self):
        rc, _ = self.invoke(['--ref=v9.9.9'])
        self.assertNotEqual(rc, 0)
        self.assertFalse(self.target.exists())
        self.assert_clean()

    def test_exact_commit_supported(self):
        rc, output = self.invoke([f'--ref={self.commit}'])
        self.assertEqual(rc, 0, output)

    def test_docker_unavailable_no_changes(self):
        rc, output = self.invoke(tty=False, env={'DOCKER_RC': '1'})
        self.assertNotEqual(rc, 0)
        self.assertLess(output.index('VB TECH PLATFORM'), output.index('Docker is not ready'))
        self.assertIn('Setup has not started', output)
        self.assertFalse((self.root / 'platform').exists())

    def test_banner_and_all_missing_tools_before_exit(self):
        (self.bin / 'docker').unlink()
        (self.bin / 'node').unlink()
        rc, output = self.invoke(tty=False, env={'PATH': str(self.bin)})
        self.assertNotEqual(rc, 0)
        for message in ['Python 3 missing', 'Node.js missing', 'Docker missing']:
            self.assertIn(message, output)
            self.assertLess(output.index('VB TECH PLATFORM'), output.index(message))
        self.assertIn('https://www.docker.com/products/docker-desktop/', output)
        self.assertIn('No files, services or settings have been changed', output)
        self.assertFalse((self.root / 'platform').exists())

    def test_help_also_starts_with_banner(self):
        rc, output = self.invoke(['--help'], tty=False)
        self.assertEqual(rc, 0)
        self.assertLess(output.index('VB TECH PLATFORM'), output.index('Usage:'))

    def test_truncated_script_does_not_execute(self):
        result = subprocess.run(['/bin/bash'], input=SCRIPT.read_text()[:SCRIPT.read_text().rfind('}')],
                                text=True, capture_output=True, env=self.env)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'platform').exists())
        self.assertEqual(self.trace_entries(), [])


if __name__ == '__main__':
    unittest.main()
