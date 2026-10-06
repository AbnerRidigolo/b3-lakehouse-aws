from datetime import date, timedelta
import io
import json
import zipfile
import pytest
from src.bronze.handler import date_windows, ingest, validate_b3, validate_bcb

DAY = date(2026, 10, 1)


def cotahist(count=3, row_date=b"20261001"):
    header = bytearray(b" " * 245)
    header[:2] = b"00"
    header[2:15] = b"COTAHIST.2026"
    header[15:23] = b"BOVESPA "
    header[23:31] = b"20261002"
    row = bytearray(b" " * 245)
    row[:2], row[2:10], row[10:12], row[24:27] = b"01", row_date, b"02", b"010"
    trailer = bytearray(header)
    trailer[:2] = b"99"
    trailer[31:42] = f"{count:011d}".encode()
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("COTAHIST_D01102026.TXT", b"\r\n".join([header, row, trailer]) + b"\r\n")
    return buffer.getvalue()


def test_cotahist_footer_counts_header_and_trailer():
    assert validate_b3(cotahist(), DAY)["trailer_count_mode"] == "all_records"
    assert validate_b3(cotahist(count=1), DAY)["trailer_count_mode"] == "quotes_only"
    with pytest.raises(ValueError, match="count mismatch"):
        validate_b3(cotahist(count=4), DAY)
    with pytest.raises(ValueError, match="trading date"):
        validate_b3(cotahist(row_date=b"20260930"), DAY)


def test_zip_html_or_unexpected_members_rejected():
    with pytest.raises(zipfile.BadZipFile):
        validate_b3(b"<html>unavailable</html>", DAY)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("../../unexpected.txt", b"x")
    with pytest.raises(ValueError, match="ZIP members"):
        validate_b3(buffer.getvalue(), DAY)


def test_windows_cover_leap_years_without_gaps_or_overlap():
    start, end = date(1986, 1, 1), date(2026, 10, 1)
    windows = list(date_windows(start, end))
    assert windows[0][0] == start and windows[-1][1] == end
    assert all((b - a).days < 3650 for a, b in windows)
    assert all(windows[i][1] + timedelta(days=1) == windows[i+1][0] for i in range(len(windows)-1))


@pytest.mark.parametrize("payload", [b"[]", b'[{"data":"30/09/2026","valor":"1"}]', b'[{"data":"01/10/2026","valor":"NaN"}]'])
def test_missing_wrong_date_or_nonfinite_bcb_fails(payload):
    with pytest.raises(ValueError):
        validate_bcb(payload, DAY)


class AWSFailure(Exception):
    def __init__(self, code):
        self.response = {"Error": {"Code": code}}


class Storage:
    def __init__(self):
        self.objects = {}
    def head_object(self, Bucket, Key):
        if Key not in self.objects:
            raise AWSFailure("404")
        return {"Metadata": self.objects[Key]["Metadata"]}
    def put_object(self, **kwargs):
        assert kwargs["IfNoneMatch"] == "*"
        if kwargs["Key"] in self.objects:
            raise AWSFailure("PreconditionFailed")
        self.objects[kwargs["Key"]] = kwargs


class Runs:
    def __init__(self):
        self.item = {}
    def update_item(self, **kwargs):
        values = kwargs["ExpressionAttributeValues"]
        if ":running" in values:
            if self.item.get("status") == "SUCCESS" or self.item.get("lease_until", 0) >= values[":now"]:
                raise AWSFailure("ConditionalCheckFailedException")
            self.item = {"status": "RUNNING", "owner_id": values[":owner"], "lease_until": values[":lease"]}
        else:
            assert self.item["owner_id"] == values[":owner"]
            self.item["status"] = values[":status"]
            self.item.pop("lease_until")
    def get_item(self, **kwargs):
        assert kwargs["ConsistentRead"]
        return {"Item": self.item}


def test_partial_failure_retry_resumes_and_success_skips_all_downloads():
    s3, runs, calls = Storage(), Runs(), []
    def download(url):
        calls.append(url)
        if 'COTAHIST' in url:
            return cotahist()
        if len(calls) == 2:
            raise TimeoutError("source unavailable")
        return json.dumps([{"data": "01/10/2026", "valor": "0.05"}]).encode()
    with pytest.raises(TimeoutError):
        ingest(DAY, s3, runs, 'bucket', download, lambda: 1000)
    assert runs.item['status'] == 'FAILED' and len(s3.objects) == 1
    result = ingest(DAY, s3, runs, 'bucket', download, lambda: 1001)
    assert result['status'] == 'SUCCESS'
    assert result['sources']['b3']['scope_rows'] == 1
    assert len(s3.objects) == 4 and sum('COTAHIST' in u for u in calls) == 1
    before = len(calls)
    assert ingest(DAY, s3, runs, 'bucket', download, lambda: 1002)['status'] == 'ALREADY_SUCCESS'
    assert len(calls) == before
