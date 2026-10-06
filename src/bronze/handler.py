"""Daily raw ingestion. Network and AWS adapters are injectable for offline tests."""
from datetime import date, datetime, timedelta
from decimal import Decimal
import hashlib
import io
import json
import os
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo
import zipfile

SERIES = {"cdi": 12, "selic": 11, "usd_brl_sell": 1}
DOWNLOAD_LIMIT = 32 * 1024 * 1024
EXPANDED_LIMIT = 128 * 1024 * 1024


def date_windows(start, end):
    if start > end:
        raise ValueError("Invalid date range")
    while start <= end:
        stop = min(end, start + timedelta(days=3649))
        yield start, stop
        start = stop + timedelta(days=1)


def reference_date(event):
    if "reference_date" in event:
        target = date.fromisoformat(event["reference_date"])
    elif "scheduled_time" in event:
        target = datetime.fromisoformat(event["scheduled_time"].replace("Z", "+00:00")).astimezone(ZoneInfo("America/Sao_Paulo")).date()
    else:
        raise ValueError("Explicit reference_date or scheduled_time is required")
    if target > datetime.now(ZoneInfo("America/Sao_Paulo")).date():
        raise ValueError("Future reference date")
    return target


def source_urls(target):
    stamp = target.strftime("%d%m%Y")
    result = {"b3": f"https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_D{stamp}.ZIP"}
    query = urlencode({"formato": "json", "dataInicial": target.strftime("%d/%m/%Y"), "dataFinal": target.strftime("%d/%m/%Y")})
    result.update({name: f"https://api.bcb.gov.br/dados/serie/bcdata.sgs.{code}/dados?{query}" for name, code in SERIES.items()})
    return result


def fetch(url):
    request = Request(url, headers={"User-Agent": "b3-lakehouse-aws/0.1"})
    with urlopen(request, timeout=20) as response:
        if response.geturl().split(":", 1)[0] != "https":
            raise ValueError("Insecure source redirect")
        payload = response.read(DOWNLOAD_LIMIT + 1)
    if len(payload) > DOWNLOAD_LIMIT:
        raise ValueError("Download size limit exceeded")
    return payload


def validate_b3(payload, target):
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        entries = archive.infolist()
        expected = f"COTAHIST_D{target:%d%m%Y}.TXT"
        if len(entries) != 1 or entries[0].filename.upper() != expected:
            raise ValueError("Unexpected ZIP members")
        if entries[0].file_size > EXPANDED_LIMIT:
            raise ValueError("Expanded file size limit exceeded")
        # Reading also validates ZIP CRC. Never extract paths to disk.
        lines = archive.read(entries[0]).splitlines()
    if len(lines) < 3 or any(len(line) != 245 for line in lines):
        raise ValueError("Invalid COTAHIST record length")
    if lines[0][:2] != b"00" or lines[-1][:2] != b"99":
        raise ValueError("Missing header or trailer")
    if lines[0][2:23] != lines[-1][2:23] or lines[0][15:23].strip() != b"BOVESPA":
        raise ValueError("Invalid COTAHIST identity")
    trailer_count = lines[-1][31:42]
    if not trailer_count.isdigit() or int(trailer_count) not in {len(lines), len(lines) - 2}:
        raise ValueError("Trailer count mismatch")
    scoped = 0
    for row in lines[1:-1]:
        if row[:2] != b"01" or row[2:10] != target.strftime("%Y%m%d").encode():
            raise ValueError("Unexpected record type or trading date")
        if row[10:12] == b"02" and row[24:27] == b"010":
            scoped += 1
    if not scoped:
        raise ValueError("No standard-lot spot records")
    return {"rows": len(lines) - 2, "scope_rows": scoped, "trailer_count_mode": "all_records" if int(trailer_count) == len(lines) else "quotes_only"}


def validate_bcb(payload, target):
    rows = json.loads(payload)
    if not isinstance(rows, list) or len(rows) != 1:
        raise ValueError("Expected one BCB observation for the reference date")
    row = rows[0]
    if datetime.strptime(row["data"], "%d/%m/%Y").date() != target:
        raise ValueError("Wrong BCB observation date")
    value = Decimal(row["valor"])
    if not value.is_finite() or value < 0:
        raise ValueError("Invalid BCB numeric value")
    return {"rows": 1}


def error_code(exc):
    return getattr(exc, "response", {}).get("Error", {}).get("Code", "")


def ingest(target, s3, table, bucket, downloader=fetch, clock=time.time):
    run_key = {"pk": f"bronze#{target.isoformat()}"}
    now = int(clock())
    owner = os.urandom(16).hex()
    try:
        table.update_item(Key=run_key,
            UpdateExpression="SET #s=:running, lease_until=:lease, owner_id=:owner, updated_at=:now, expires_at=:expiry",
            ConditionExpression="(attribute_not_exists(#s) OR #s <> :success) AND (attribute_not_exists(lease_until) OR lease_until < :now)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":running": "RUNNING", ":success": "SUCCESS", ":lease": now + 300,
                ":owner": owner, ":now": now, ":expiry": now + 90 * 86400})
    except Exception as exc:
        if error_code(exc) != "ConditionalCheckFailedException":
            raise
        previous = table.get_item(Key=run_key, ConsistentRead=True).get("Item", {})
        if previous.get("status") == "SUCCESS":
            return {"reference_date": target.isoformat(), "status": "ALREADY_SUCCESS"}
        raise RuntimeError("Reference date is already running") from exc
    results = {}
    try:
        for name, url in source_urls(target).items():
            extension = "zip" if name == "b3" else "json"
            key = f"bronze/source={name}/reference_date={target.isoformat()}/raw.{extension}"
            try:
                prior = s3.head_object(Bucket=bucket, Key=key)
            except Exception as exc:
                if error_code(exc) not in {"404", "NoSuchKey", "NotFound"}:
                    raise
                prior = None
            if prior:
                meta = prior["Metadata"]
                if meta.get("validated") != "v1" or meta.get("reference-date") != target.isoformat():
                    raise ValueError("Existing bronze object is not validated")
                results[name] = {"key": key, "rows": int(meta["rows"]), "sha256": meta["sha256"]}
                if name == "b3":
                    results[name].update(scope_rows=int(meta["scope-rows"]), trailer_count_mode=meta["trailer-count-mode"])
                continue
            payload = downloader(url)
            checked = validate_b3(payload, target) if name == "b3" else validate_bcb(payload, target)
            digest = hashlib.sha256(payload).hexdigest()
            s3.put_object(Bucket=bucket, Key=key, Body=payload, IfNoneMatch="*", ServerSideEncryption="AES256",
                ContentType="application/zip" if name == "b3" else "application/json",
                Metadata={"validated": "v1", "reference-date": target.isoformat(), "rows": str(checked["rows"]), "sha256": digest,
                    **({"scope-rows": str(checked["scope_rows"]), "trailer-count-mode": checked["trailer_count_mode"]} if name == "b3" else {})})
            results[name] = {"key": key, "sha256": digest, **checked}
        table.update_item(Key=run_key,
            UpdateExpression="SET #s=:status, sources=:sources, updated_at=:now REMOVE lease_until",
            ConditionExpression="owner_id=:owner",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":status": "SUCCESS", ":sources": results, ":now": int(clock()), ":owner": owner})
        return {"reference_date": target.isoformat(), "status": "SUCCESS", "sources": results}
    except Exception as exc:
        table.update_item(Key=run_key,
            UpdateExpression="SET #s=:status, error_type=:error, updated_at=:now REMOVE lease_until",
            ConditionExpression="owner_id=:owner",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":status": "FAILED", ":error": type(exc).__name__, ":now": int(clock()), ":owner": owner})
        raise


def lambda_handler(event, context):
    import boto3
    target = reference_date(event)
    return ingest(target, boto3.client("s3"), boto3.resource("dynamodb").Table(os.environ["RUNS_TABLE"]), os.environ["BRONZE_BUCKET"])
