#!/usr/bin/env python3
"""Preflight and store Vault's one-time initialization bundle in Secrets Manager."""

import argparse
import hashlib
import importlib
import json
import sys
from typing import Any, Dict, List, Optional, Tuple, cast

EXPECTED_SHARES = 5
EXPECTED_THRESHOLD = 3
MAX_SECRET_BYTES = 65536


class BootstrapError(Exception):
    """An operational error safe to print."""


def _role_identity(role_arn: str) -> Tuple[str, str]:
    parts = role_arn.split(":", 5)
    if len(parts) != 6 or parts[2] != "iam" or not parts[5].startswith("role/"):
        raise BootstrapError("Expected a valid IAM role ARN.")
    if not parts[5][5:]:
        raise BootstrapError("Expected a valid IAM role ARN.")
    return parts[1], parts[4]


def _assumed_session(role_arn: str, region: str, profile: Optional[str]) -> Any:
    session_args = {"region_name": region}
    if profile:
        session_args["profile_name"] = profile

    try:
        boto3 = importlib.import_module("boto3")
        source = boto3.Session(**session_args)
        assumed = source.client("sts").assume_role(
            RoleArn=role_arn,
            RoleSessionName="vault-bootstrap",
        )
        credentials = assumed["Credentials"]
        session = boto3.Session(
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials["SessionToken"],
            region_name=region,
        )
        identity = session.client("sts").get_caller_identity()
    except Exception:
        raise BootstrapError("Could not assume and verify the configured bootstrap role.") from None

    partition, account = _role_identity(role_arn)
    caller_arn = identity.get("Arn", "")
    caller_parts = caller_arn.split(":", 5)
    assumed_user_value = assumed.get("AssumedRoleUser", {})
    assumed_user = cast(Dict[str, Any], assumed_user_value) if isinstance(assumed_user_value, dict) else {}
    if len(caller_parts) != 6 or caller_parts[2] != "sts":
        raise BootstrapError("AWS caller identity is not an assumed IAM role.")
    if (
        caller_parts[1] != partition
        or caller_parts[4] != account
        or caller_arn != assumed_user.get("Arn")
        or identity.get("UserId") != assumed_user.get("AssumedRoleId")
        or identity.get("Account") != account
    ):
        raise BootstrapError("AWS caller identity does not match the configured bootstrap role and account.")
    return session


def _describe_empty_secret(client: Any, secret_id: str, kms_key_arn: str) -> Dict[str, Any]:
    try:
        metadata = client.describe_secret(SecretId=secret_id)
    except Exception:
        raise BootstrapError("Could not describe the configured recovery secret.") from None

    if metadata.get("KmsKeyId") != kms_key_arn:
        raise BootstrapError("Recovery secret is not encrypted with the expected KMS key.")
    versions_value = metadata.get("VersionIdsToStages", {})
    if not isinstance(versions_value, dict):
        raise BootstrapError("Recovery secret version metadata is invalid.")
    versions = cast(Dict[str, Any], versions_value)
    return versions


def _bundle_from_json(raw: bytes) -> str:
    if not raw or len(raw) > MAX_SECRET_BYTES:
        raise BootstrapError("Initialization JSON is empty or exceeds the Secrets Manager size limit.")
    try:
        response_value = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise BootstrapError("Initialization output is not valid JSON.") from None
    if not isinstance(response_value, dict):
        raise BootstrapError("Initialization output must be a JSON object.")
    response = cast(Dict[str, Any], response_value)

    shares = response.get("recovery_keys_b64")
    if not isinstance(shares, list):
        raise BootstrapError("Initialization output must contain exactly five recovery shares.")
    shares = cast(List[Any], shares)
    if len(shares) != EXPECTED_SHARES:
        raise BootstrapError("Initialization output must contain exactly five recovery shares.")
    root_token = response.get("root_token")
    if any(not isinstance(share, str) or not share for share in shares):
        raise BootstrapError("Initialization output contains an empty or invalid recovery share.")
    if not isinstance(root_token, str) or not root_token:
        raise BootstrapError("Initialization output does not contain a non-empty root token.")

    share_count = response.get("recovery_keys_shares", EXPECTED_SHARES)
    threshold = response.get("recovery_keys_threshold", EXPECTED_THRESHOLD)
    if share_count != EXPECTED_SHARES or threshold != EXPECTED_THRESHOLD:
        raise BootstrapError("Initialization output recovery share count or threshold is not 5-of-3.")

    bundle: Dict[str, Any] = {
        "recovery_keys_b64": shares,
        "recovery_keys_shares": EXPECTED_SHARES,
        "recovery_keys_threshold": EXPECTED_THRESHOLD,
        "root_token": root_token,
    }
    encoded = json.dumps(bundle, sort_keys=True, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > MAX_SECRET_BYTES:
        raise BootstrapError("Recovery bundle exceeds the Secrets Manager size limit.")
    return encoded


def _version_token(secret_id: str, bundle_json: str) -> str:
    payload = (secret_id + "\0" + bundle_json).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def preflight(role_arn: str, secret_id: str, kms_key_arn: str, region: str, profile: Optional[str]) -> None:
    """Verify bootstrap access and confirm the recovery secret is empty.

    Assumes the configured bootstrap role, validates its AWS identity, and
    checks that the secret uses the expected KMS key and has no versions.
    Run this before initializing Vault; it never reads a secret value.
    """
    session = _assumed_session(role_arn, region, profile)
    versions = _describe_empty_secret(session.client("secretsmanager"), secret_id, kms_key_arn)
    if versions:
        raise BootstrapError("Recovery secret already has a version; refusing to initialize Vault.")


def store(
    role_arn: str,
    secret_id: str,
    kms_key_arn: str,
    region: str,
    profile: Optional[str],
    raw: bytes,
) -> bool:
    """Store and verify a captured Vault init response without printing it.

    Validates the five recovery shares, 3-of-5 threshold, and root token,
    writes the bundle with a deterministic version token, and verifies its
    Secrets Manager version metadata. Returns True for an identical retry.
    """
    bundle_json = _bundle_from_json(raw)
    version_token = _version_token(secret_id, bundle_json)
    session = _assumed_session(role_arn, region, profile)
    client = session.client("secretsmanager")
    versions = _describe_empty_secret(client, secret_id, kms_key_arn)

    if versions:
        if set(versions) == {version_token} and "AWSCURRENT" in versions[version_token]:
            return True
        raise BootstrapError("Recovery secret has an unexpected version; refusing to overwrite it.")

    try:
        result = client.put_secret_value(
            SecretId=secret_id,
            SecretString=bundle_json,
            ClientRequestToken=version_token,
        )
        if result.get("VersionId") != version_token:
            raise BootstrapError("Secrets Manager returned an unexpected version identifier.")
        versions_after = _describe_empty_secret(client, secret_id, kms_key_arn)
        if set(versions_after) != {version_token} or "AWSCURRENT" not in versions_after[version_token]:
            raise BootstrapError("Stored version was not confirmed as the current recovery secret.")
    except BootstrapError:
        raise
    except Exception:
        raise BootstrapError(
            "Secrets Manager write failed. Do not reinitialize Vault; retry storage only with the same captured JSON."
        ) from None
    return False


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    for operation in ("preflight", "store"):
        command = subparsers.add_parser(operation)
        command.add_argument("--role-arn", required=True)
        command.add_argument("--secret-id", required=True)
        command.add_argument("--kms-key-arn", required=True)
        command.add_argument("--region", required=True)
        command.add_argument("--profile")
    args = parser.parse_args(argv)

    try:
        if args.operation == "preflight":
            preflight(args.role_arn, args.secret_id, args.kms_key_arn, args.region, args.profile)
            print("Bootstrap preflight passed; recovery secret is empty and correctly encrypted.")
        else:
            raw = sys.stdin.buffer.read(MAX_SECRET_BYTES + 1)
            already_stored = store(
                args.role_arn,
                args.secret_id,
                args.kms_key_arn,
                args.region,
                args.profile,
                raw,
            )
            if already_stored:
                print("Recovery bundle already stored; no new secret version created.")
            else:
                print("Recovery bundle stored and verified in Secrets Manager.")
        return 0
    except BootstrapError as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
