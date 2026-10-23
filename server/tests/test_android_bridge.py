import subprocess
import unittest
from unittest.mock import Mock, call

from server.app import AndroidPortReverse


class AndroidPortReverseTests(unittest.TestCase):
    def bridge(self, *responses):
        bridge = AndroidPortReverse("adb", 8787)
        bridge._run = Mock(side_effect=responses)
        return bridge

    def test_only_connected_authorized_devices_are_mapped(self):
        bridge = self.bridge(
            "List of devices attached\nphone device\nlocked unauthorized\nlost offline\n",
            "",
            "8787\n",
        )
        bridge.restore()
        self.assertEqual(bridge._run.call_args_list, [
            call("devices"),
            call("-s", "phone", "reverse", "--list"),
            call("-s", "phone", "reverse", "tcp:8787", "tcp:8787"),
        ])

    def test_existing_mapping_is_not_rewritten(self):
        bridge = self.bridge(
            "phone device\n", "UsbFfs tcp:8787 tcp:8787\nUsbFfs tcp:9000 tcp:9000\n"
        )
        bridge.restore()
        self.assertEqual(bridge._run.call_count, 2)

    def test_mapping_is_restored_again_after_reconnect(self):
        bridge = self.bridge(
            "phone device\n", "", "8787\n",
            "phone device\n", "UsbFfs tcp:8787 tcp:8787\n",
            "\n",
            "phone device\n", "UsbFfs tcp:9000 tcp:9000\n", "8787\n",
        )
        for _ in range(4):
            bridge.restore()
        writes = [
            args for args in bridge._run.call_args_list
            if args == call("-s", "phone", "reverse", "tcp:8787", "tcp:8787")
        ]
        self.assertEqual(len(writes), 2)

    def test_disconnect_during_mapping_does_not_block_other_devices(self):
        bridge = self.bridge(
            "lost device\nphone device\n",
            subprocess.CalledProcessError(1, "adb"),
            "",
            "8787\n",
        )
        bridge.restore()
        self.assertEqual(
            bridge._run.call_args_list[-1],
            call("-s", "phone", "reverse", "tcp:8787", "tcp:8787"),
        )


if __name__ == "__main__":
    unittest.main()
