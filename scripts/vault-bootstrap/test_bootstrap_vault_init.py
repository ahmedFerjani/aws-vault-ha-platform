"""Focused tests for bootstrap_vault_init; all AWS calls are mocked."""

import json
import types
import unittest
from unittest.mock import patch
from typing import Any, Dict, List

import bootstrap_vault_init as bootstrap

ROLE_ARN = "arn:aws:iam::123456789012:role/platform/vault-bootstrap"
SECRET = "vault-ha-dev/bootstrap-recovery"
KEY_ARN = "arn:aws:kms:us-east-1:123456789012:key/test-key"
SHARES = ["dummy-share-1", "dummy-share-2", "dummy-share-3", "dummy-share-4", "dummy-share-5"]
ROOT_TOKEN = "dummy-root-token"


def init_json(shares: List[str] = SHARES, root_token: str = ROOT_TOKEN) -> bytes:
    return json.dumps(
        {
            "recovery_keys_b64": shares,
            "recovery_keys_shares": 5,
            "recovery_keys_threshold": 3,
            "root_token": root_token,
        }
    ).encode()


class FakeSecrets:
    def __init__(self):
        self.versions: Dict[str, List[str]] = {}
        self.put_calls: List[Dict[str, str]] = []
        self.fail_put = False
        self.kms_key = KEY_ARN

    def describe_secret(self, SecretId: str) -> Dict[str, Any]:
        if SecretId != SECRET:
            raise AssertionError("unexpected secret")
        return {"KmsKeyId": self.kms_key, "VersionIdsToStages": dict(self.versions)}

    def put_secret_value(self, **kwargs: str) -> Dict[str, str]:
        self.put_calls.append(kwargs)
        if self.fail_put:
            raise RuntimeError("synthetic failure")
        token = kwargs["ClientRequestToken"]
        self.versions[token] = ["AWSCURRENT"]
        return {"VersionId": token}


class FakeSession:
    def __init__(self, secrets: FakeSecrets):
        self.secrets = secrets
        self.wrong_identity = False

    def client(self, service: str) -> Any:
        if service == "secretsmanager":
            return self.secrets
        if service == "sts":
            return self
        raise AssertionError("unexpected AWS service")

    def assume_role(self, **_: Any) -> Dict[str, Any]:
        return {
            "Credentials": {
                "AccessKeyId": "dummy",
                "SecretAccessKey": "dummy",
                "SessionToken": "dummy",
            },
            "AssumedRoleUser": {
                "Arn": "arn:aws:sts::123456789012:assumed-role/vault-bootstrap/session",
                "AssumedRoleId": "AROAEXAMPLE:vault-bootstrap",
            },
        }

    def get_caller_identity(self) -> Dict[str, str]:
        role = "different-role" if self.wrong_identity else "vault-bootstrap"
        role_id = "AROAOTHER" if self.wrong_identity else "AROAEXAMPLE"
        return {
            "Account": "123456789012",
            "Arn": f"arn:aws:sts::123456789012:assumed-role/{role}/session",
            "UserId": f"{role_id}:vault-bootstrap",
        }


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.secrets = FakeSecrets()
        self.session = FakeSession(self.secrets)

        def fake_session(**_: Any) -> FakeSession:
            return self.session

        fake_boto3 = types.SimpleNamespace(Session=fake_session)
        self.import_patch = patch.object(bootstrap.importlib, "import_module", return_value=fake_boto3)
        self.import_patch.start()
        self.addCleanup(self.import_patch.stop)

    def preflight(self) -> None:
        bootstrap.preflight(ROLE_ARN, SECRET, KEY_ARN, "us-east-1", None)

    def test_preflight_accepts_empty_secret_with_expected_key(self):
        self.preflight()

    def test_preflight_rejects_existing_version(self):
        self.secrets.versions["old-version"] = ["AWSCURRENT"]
        self.assertRaises(bootstrap.BootstrapError, self.preflight)

    def test_preflight_rejects_wrong_kms_key(self):
        self.secrets.kms_key = "arn:aws:kms:us-east-1:123456789012:key/wrong-key"
        self.assertRaises(bootstrap.BootstrapError, self.preflight)

    def test_preflight_rejects_wrong_assumed_role_identity(self):
        self.session.wrong_identity = True
        with self.assertRaises(bootstrap.BootstrapError):
            self.preflight()

    def test_store_rejects_malformed_json_and_wrong_share_count(self):
        self.assertRaises(
            bootstrap.BootstrapError,
            bootstrap.store,
            ROLE_ARN,
            SECRET,
            KEY_ARN,
            "us-east-1",
            None,
            b"not-json",
        )
        self.assertRaises(
            bootstrap.BootstrapError,
            bootstrap.store,
            ROLE_ARN,
            SECRET,
            KEY_ARN,
            "us-east-1",
            None,
            init_json(SHARES[:4]),
        )
        self.assertRaises(
            bootstrap.BootstrapError,
            bootstrap.store,
            ROLE_ARN,
            SECRET,
            KEY_ARN,
            "us-east-1",
            None,
            init_json(root_token=""),
        )
        self.assertEqual(self.secrets.put_calls, [])

    def test_store_writes_bundle_without_printing_sensitive_values(self):
        import contextlib
        import io

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            already_stored = bootstrap.store(ROLE_ARN, SECRET, KEY_ARN, "us-east-1", None, init_json())
        self.assertFalse(already_stored)
        self.assertEqual(len(self.secrets.put_calls), 1)
        stored = json.loads(self.secrets.put_calls[0]["SecretString"])
        self.assertEqual(stored["recovery_keys_b64"], SHARES)
        self.assertEqual(stored["recovery_keys_shares"], 5)
        self.assertEqual(stored["recovery_keys_threshold"], 3)
        self.assertEqual(stored["root_token"], ROOT_TOKEN)
        self.assertNotIn(ROOT_TOKEN, output.getvalue())
        self.assertTrue(all(share not in output.getvalue() for share in SHARES))

    def test_identical_bundle_retry_does_not_create_new_version(self):
        first = bootstrap.store(ROLE_ARN, SECRET, KEY_ARN, "us-east-1", None, init_json())
        second = bootstrap.store(ROLE_ARN, SECRET, KEY_ARN, "us-east-1", None, init_json())
        self.assertFalse(first)
        self.assertTrue(second)
        self.assertEqual(len(self.secrets.put_calls), 1)

    def test_store_rejects_different_existing_bundle(self):
        bootstrap.store(ROLE_ARN, SECRET, KEY_ARN, "us-east-1", None, init_json())
        self.assertRaises(
            bootstrap.BootstrapError,
            bootstrap.store,
            ROLE_ARN,
            SECRET,
            KEY_ARN,
            "us-east-1",
            None,
            init_json(root_token="different"),
        )
        self.assertEqual(len(self.secrets.put_calls), 1)

    def test_store_failure_is_sanitized(self):
        self.secrets.fail_put = True
        self.assertRaisesRegex(
            bootstrap.BootstrapError,
            "Do not reinitialize Vault",
            bootstrap.store,
            ROLE_ARN,
            SECRET,
            KEY_ARN,
            "us-east-1",
            None,
            init_json(),
        )


if __name__ == "__main__":
    unittest.main()
