"""Protect a Terraform plan artifact; never print keys or plan contents."""
import argparse
import base64
import os
from pathlib import Path

from nacl.exceptions import CryptoError
from nacl.secret import Aead


def transform(operation: str, source: Path, destination: Path, key: str, context: str):
    if not context:
        raise ValueError("Plan context is required")
    decoded = base64.b64decode(key, validate=True)
    if len(decoded) != Aead.KEY_SIZE:
        raise ValueError("Plan key must contain 32 bytes")
    box = Aead(decoded)
    payload = source.read_bytes()
    aad = context.encode("utf-8")
    result = box.encrypt(payload, aad) if operation == "encrypt" else box.decrypt(payload, aad)
    # Authenticate before creating the output; fail if an output already exists.
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["encrypt", "decrypt"])
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        transform(args.operation, args.source, args.destination,
                  os.environ["TF_PLAN_ENCRYPTION_KEY"], os.environ["PLAN_CONTEXT"])
    except (ValueError, KeyError, OSError, CryptoError):
        parser.exit(1, "Plan protection failed; no plan contents or key disclosed.\n")


if __name__ == "__main__":
    main()
