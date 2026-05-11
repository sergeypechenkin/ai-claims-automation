import importlib
import os
import sys
import types
import unittest
from unittest.mock import patch


def load_function_app_module():
    os.environ.pop("APPLICATIONINSIGHTS_CONNECTION_STRING", None)
    fake_extract_text = types.ModuleType("extract_text")
    fake_extract_text.extract_file_info = lambda uri: "mock-file-info"
    fake_extract_text.analyze_text = lambda text: "mock-analysis"
    sys.modules["extract_text"] = fake_extract_text
    sys.modules.pop("function_app", None)
    return importlib.import_module("function_app")


class TestTracingConfiguration(unittest.TestCase):
    def setUp(self):
        self._original_connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
        self._original_extract_text_module = sys.modules.get("extract_text")
        self._original_function_app_module = sys.modules.get("function_app")

    def tearDown(self):
        if self._original_connection_string is None:
            os.environ.pop("APPLICATIONINSIGHTS_CONNECTION_STRING", None)
        else:
            os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"] = self._original_connection_string

        if self._original_extract_text_module is None:
            sys.modules.pop("extract_text", None)
        else:
            sys.modules["extract_text"] = self._original_extract_text_module

        if self._original_function_app_module is None:
            sys.modules.pop("function_app", None)
        else:
            sys.modules["function_app"] = self._original_function_app_module

    def test_configures_exporter_when_connection_string_is_set(self):
        function_app = load_function_app_module()

        with patch.object(function_app, "configure_azure_monitor") as configure_mock:
            with patch.dict(
                os.environ,
                {"APPLICATIONINSIGHTS_CONNECTION_STRING": "InstrumentationKey=test-key"},
                clear=False,
            ):
                function_app._configure_tracing()

        configure_mock.assert_called_once_with(connection_string="InstrumentationKey=test-key")

    def test_skips_exporter_configuration_without_connection_string(self):
        function_app = load_function_app_module()

        with patch.object(function_app, "configure_azure_monitor") as configure_mock:
            function_app._configure_tracing()

        configure_mock.assert_not_called()
