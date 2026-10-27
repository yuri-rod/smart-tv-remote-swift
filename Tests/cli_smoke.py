"""Exercise command results against loopback HTTP fixtures, without a TV."""
import http.server
import pathlib
import subprocess
import threading
import unittest

BINARY = pathlib.Path(__file__).resolve().parents[1] / '.build/debug/smartcast'


class DeviceHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(self.server.response_status)
        self.end_headers()
        self.wfile.write(b'fixture response')

    def log_message(self, *_):
        pass


class CommandResults(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.servers = []
        for port in (52235, 8060):
            server = http.server.ThreadingHTTPServer(('127.0.0.1', port), DeviceHandler)
            cls.addClassCleanup(server.server_close)
            cls.addClassCleanup(server.shutdown)
            cls.servers.append(server)
            threading.Thread(target=server.serve_forever, daemon=True).start()

    def run_command(self, command, status):
        for server in self.servers:
            server.response_status = status
        return subprocess.run(
            [str(BINARY), '--transport', 'roku', command, '127.0.0.1'],
            capture_output=True, text=True, timeout=10,
        )

    def test_device_failures_exit_nonzero(self):
        for command in ('pause', 'resume', 'stop', 'mute'):
            with self.subTest(command=command):
                result = self.run_command(command, 500)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('Error', result.stdout + result.stderr)
                self.assertNotIn('playback on', result.stdout)

    def test_successful_commands_exit_zero(self):
        for command in ('pause', 'resume', 'stop', 'mute'):
            with self.subTest(command=command):
                result = self.run_command(command, 200)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('Error', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
