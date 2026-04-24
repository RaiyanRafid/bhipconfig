import importlib.machinery
import importlib.util
import pathlib
import unittest
from io import StringIO
from unittest import mock


SCRIPT_PATH = pathlib.Path("/var/tools/bhipconfig")


def load_module():
    loader = importlib.machinery.SourceFileLoader("bhipconfig_module", str(SCRIPT_PATH))
    spec = importlib.util.spec_from_loader("bhipconfig_module", loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class BhipConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def make_summary(self, addresses):
        return self.mod.InterfaceSummary(
            name="eth0",
            state="UP",
            addresses=list(addresses),
            gateways={"inet": "10.0.0.1"},
            dns_servers=["1.1.1.1"],
            mac="00:11:22:33:44:55",
            mtu=1500,
        )

    def make_app(self, addresses):
        with mock.patch.object(self.mod, "NetworkController") as controller_cls:
            controller = controller_cls.return_value
            controller.default_interface_name.return_value = "eth0"
            controller.summary_for.return_value = self.make_summary(addresses)
            controller.displayable_interfaces.return_value = [self.make_summary(addresses)]
            controller.resolver_mode = "resolv.conf"
            app = self.mod.BhipConfigApp()
        app.current_interface = "eth0"
        return app, controller

    def test_normalize_cidr_ipv4(self):
        self.assertEqual(self.mod.normalize_cidr("192.168.1.10/24"), "192.168.1.10/24")

    def test_normalize_cidr_ipv6(self):
        self.assertEqual(self.mod.normalize_cidr("2001:db8::1/64"), "2001:db8::1/64")

    def test_parse_dns_servers(self):
        result = self.mod.parse_dns_servers("1.1.1.1, 8.8.8.8  2606:4700:4700::1111")
        self.assertEqual(result, ["1.1.1.1", "8.8.8.8", "2606:4700:4700::1111"])

    def test_render_resolv_conf_keeps_non_nameserver_lines(self):
        existing = "search example.com\nnameserver 9.9.9.9\noptions ndots:2\n"
        rendered = self.mod.render_resolv_conf(existing, ["1.1.1.1", "8.8.8.8"])
        self.assertEqual(
            rendered,
            "nameserver 1.1.1.1\nnameserver 8.8.8.8\n\nsearch example.com\noptions ndots:2\n",
        )

    def test_gateway_command_uses_onlink_when_gateway_outside_subnet(self):
        controller = self.mod.NetworkController()
        with mock.patch.object(controller, "current_addresses", return_value=["10.10.10.5/32"]):
            cmd = controller.build_gateway_command("eth0", "10.10.10.1")
        self.assertEqual(cmd[-1], "onlink")

    def test_snapshot_round_trip(self):
        snapshot = self.mod.Snapshot(
            interface="eth0",
            link_up=True,
            addresses=["192.168.1.10/24"],
            default_routes=[{"dev": "eth0", "gateway": "192.168.1.1", "family": "inet"}],
            resolver_mode="resolv.conf",
            dns_servers=["1.1.1.1"],
            resolv_conf="nameserver 1.1.1.1\n",
        )
        restored = self.mod.Snapshot.from_dict(snapshot.to_dict())
        self.assertEqual(restored, snapshot)

    def test_prompt_input_keyboard_interrupt_raises_prompt_cancelled(self):
        with mock.patch("builtins.input", side_effect=KeyboardInterrupt):
            with self.assertRaises(self.mod.PromptCancelled):
                self.mod.prompt_input("Prompt: ")

    def test_prompt_timeout_keyboard_interrupt_raises_prompt_cancelled(self):
        with mock.patch.object(self.mod.select, "select", side_effect=KeyboardInterrupt):
            with self.assertRaises(self.mod.PromptCancelled):
                self.mod.prompt_timeout("Prompt: ", 1)

    def test_build_main_menu_actions_for_no_ip_interface(self):
        app, _ = self.make_app([])
        labels = [action.label for action in app.build_main_menu_actions()]
        self.assertEqual(
            labels,
            ["Add IP", "Set Gateway", "Set DNS", "Interface Manage", "Restart Network", "Refresh"],
        )

    def test_build_main_menu_actions_for_existing_ip_hides_add(self):
        app, _ = self.make_app(["10.0.0.10/24"])
        labels = [action.label for action in app.build_main_menu_actions()]
        self.assertEqual(
            labels,
            ["Change IP", "Remove IP", "Set Gateway", "Set DNS", "Interface Manage", "Restart Network", "Refresh"],
        )

    def test_build_main_menu_actions_mixed_ipv4_ipv6_still_hides_add(self):
        app, _ = self.make_app(["10.0.0.10/24", "2001:db8::10/64"])
        labels = [action.label for action in app.build_main_menu_actions()]
        self.assertNotIn("Add IP", labels)
        self.assertEqual(labels[:2], ["Change IP", "Remove IP"])

    def test_render_uses_dynamic_numbering_without_gaps(self):
        app, _ = self.make_app([])
        actions = app.build_main_menu_actions()
        with mock.patch("sys.stdout", new_callable=StringIO) as stdout:
            app.render(actions)
        output = stdout.getvalue()
        self.assertIn("[1] Add IP", output)
        self.assertIn("[2] Set Gateway", output)
        self.assertIn("[3] Set DNS", output)
        self.assertIn("[4] Interface Manage", output)
        self.assertIn("[5] Restart Network", output)
        self.assertIn("[6] Refresh", output)
        self.assertIn("[0] Exit", output)

    def test_choose_existing_address_prompts_when_multiple_addresses_exist(self):
        app, _ = self.make_app(["10.0.0.10/24", "2001:db8::10/64"])
        with mock.patch.object(self.mod, "prompt_input", return_value="2"):
            selected = app.choose_existing_address()
        self.assertEqual(selected, "2001:db8::10/64")

    def test_plan_change_ip_orders_add_gateway_dns_remove(self):
        controller = self.mod.NetworkController()
        dns_operation = self.mod.Operation("DNS", "set-dns", lambda: None)
        with mock.patch.object(controller, "current_addresses", return_value=["10.0.0.10/24"]), \
             mock.patch.object(controller, "plan_set_dns", return_value=[dns_operation]):
            operations = controller.plan_change_ip(
                "eth0",
                "10.0.0.10/24",
                "10.0.0.20/24",
                gateway="10.0.0.1",
                dns_servers=["1.1.1.1"],
            )
        self.assertEqual(
            [operation.preview for operation in operations],
            [
                "ip addr add 10.0.0.20/24 dev eth0",
                "ip -4 route replace default via 10.0.0.1 dev eth0",
                "set-dns",
                "ip addr del 10.0.0.10/24 dev eth0",
            ],
        )

    def test_remove_ip_yes_replacement_path_reuses_replace_flow(self):
        app, _ = self.make_app(["10.0.0.10/24"])
        with mock.patch.object(app, "choose_existing_address", return_value="10.0.0.10/24"), \
             mock.patch.object(self.mod, "prompt_yes_no", side_effect=[True, True]), \
             mock.patch.object(app, "run_replace_flow") as replace_flow, \
             mock.patch.object(app, "execute_plan") as execute_plan:
            app.action_remove_ip()
        replace_flow.assert_called_once_with(title="Change IP", old_cidr="10.0.0.10/24")
        execute_plan.assert_not_called()

    def test_remove_ip_no_replacement_uses_typed_remove_confirmation(self):
        app, controller = self.make_app(["10.0.0.10/24"])
        controller.plan_remove_ip.return_value = [self.mod.Operation("Remove", "ip addr del ...", lambda: None)]
        with mock.patch.object(app, "choose_existing_address", return_value="10.0.0.10/24"), \
             mock.patch.object(self.mod, "prompt_yes_no", side_effect=[True, False]), \
             mock.patch.object(app, "execute_plan") as execute_plan:
            app.action_remove_ip()
        execute_plan.assert_called_once()
        _, kwargs = execute_plan.call_args
        self.assertEqual(kwargs["action"], "remove_ip")
        self.assertEqual(kwargs["confirm_mode"], "typed")
        self.assertEqual(kwargs["confirm_value"], "REMOVE")

    def test_execute_plan_typed_confirmation_cancels_cleanly_on_wrong_input(self):
        app, controller = self.make_app(["10.0.0.10/24"])
        operations = [self.mod.Operation("Remove", "ip addr del ...", lambda: None)]
        with mock.patch.object(self.mod, "prompt_input", return_value="WRONG"):
            app.execute_plan("Remove IP", operations, action="remove_ip", confirm_mode="typed", confirm_value="REMOVE")
        controller.capture_snapshot.assert_not_called()
        self.assertEqual(app.message, "Remove IP cancelled.")

    def test_prompt_ip_wizard_rejects_invalid_cidr(self):
        app, _ = self.make_app([])
        with mock.patch.object(self.mod, "prompt_input", side_effect=["bad-cidr"]):
            result = app.prompt_ip_wizard(title="Add IP", existing_addresses=[])
        self.assertIsNone(result)
        self.assertIn("Invalid CIDR", app.message)

    def test_prompt_ip_wizard_rejects_duplicate_ip(self):
        app, _ = self.make_app(["10.0.0.10/24"])
        with mock.patch.object(self.mod, "prompt_input", side_effect=["10.0.0.10/24"]):
            result = app.prompt_ip_wizard(title="Change IP", existing_addresses=["10.0.0.10/24"])
        self.assertIsNone(result)
        self.assertIn("already assigned", app.message)

    def test_prompt_ip_wizard_rejects_gateway_family_mismatch(self):
        app, _ = self.make_app([])
        with mock.patch.object(self.mod, "prompt_input", side_effect=["10.0.0.20/24", "2001:db8::1"]):
            result = app.prompt_ip_wizard(title="Add IP", existing_addresses=[])
        self.assertIsNone(result)
        self.assertEqual(app.message, "Gateway family must match the new IP address family.")

    def test_prompt_ip_wizard_rejects_invalid_dns(self):
        app, _ = self.make_app([])
        with mock.patch.object(self.mod, "prompt_input", side_effect=["10.0.0.20/24", "", "bad-dns"]):
            result = app.prompt_ip_wizard(title="Add IP", existing_addresses=[])
        self.assertIsNone(result)
        self.assertIn("Invalid DNS entry", app.message)

    def test_guard_required_covers_add_with_gateway_change_and_remove(self):
        app, _ = self.make_app([])
        self.assertTrue(app.guard_required("add_ip_with_gateway"))
        self.assertTrue(app.guard_required("change_ip"))
        self.assertTrue(app.guard_required("remove_ip"))
        self.assertFalse(app.guard_required("add_ip"))

    def test_run_exits_cleanly_on_main_menu_interrupt(self):
        app, _ = self.make_app(["10.0.0.10/24"])
        with mock.patch.object(app, "render"), \
             mock.patch.object(self.mod, "prompt_input", side_effect=self.mod.PromptCancelled), \
             mock.patch("sys.stdout", new_callable=StringIO) as stdout:
            rc = app.run()
        self.assertEqual(rc, 130)
        self.assertIn("Exiting bhipconfig.", stdout.getvalue())

    def test_run_cancels_current_action_on_interrupt(self):
        app, _ = self.make_app(["10.0.0.10/24"])
        with mock.patch.object(app, "render"), \
             mock.patch.object(app, "action_change_ip", side_effect=self.mod.PromptCancelled), \
             mock.patch.object(self.mod, "prompt_input", side_effect=["1", "0"]):
            rc = app.run()
        self.assertEqual(rc, 0)
        self.assertEqual(app.message, "Current action cancelled.")


if __name__ == "__main__":
    unittest.main()
