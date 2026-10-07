"""Daily Glue 5.0 Spark -> Iceberg v2. No automatic job start or backfill.

Each table commits atomically; a two-table transaction is not provided by Iceberg.
SUCCESS is recorded only after both MERGEs and read-back validation. Retry repairs
a partial commit using the same immutable bronze inputs.
"""
import hashlib
import io
import json
import sys
import time
import uuid
import zipfile
from datetime import date


def run():
    import boto3
    from awsglue.utils import getResolvedOptions
    from awsglue.context import GlueContext
    from awsglue.job import Job
    from pyspark.context import SparkContext
    from pyspark.sql import functions as F, types as T
    from bronze_lib import DOWNLOAD_LIMIT, validate_b3
    from silver_lib import parse_quote, parse_rate, safe_identifier

    args = getResolvedOptions(sys.argv, ["JOB_NAME", "reference_date", "bronze_bucket", "silver_bucket", "runs_table", "database"])
    target = date.fromisoformat(args["reference_date"])
    database = safe_identifier(args["database"])
    table = boto3.resource("dynamodb").Table(args["runs_table"])
    bronze = table.get_item(Key={"pk": f"bronze#{target}"}, ConsistentRead=True).get("Item", {})
    if bronze.get("status") != "SUCCESS":
        raise ValueError("Bronze must be SUCCESS before processing")
    key, owner, now = {"pk": f"silver#{target}"}, uuid.uuid4().hex, int(time.time())
    # Lease exceeds Terraform's ten-minute timeout. Glue also limits concurrency to one.
    table.update_item(Key=key,
        UpdateExpression="SET #s=:running, owner_id=:owner, lease_until=:lease, updated_at=:now, expires_at=:expiry",
        ConditionExpression="attribute_not_exists(lease_until) OR lease_until < :now",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":running": "RUNNING", ":owner": owner, ":lease": now + 900, ":now": now, ":expiry": now + 90 * 86400})
    try:
        s3 = boto3.client("s3")
        payloads = {}
        for source in ["b3", "cdi", "selic", "usd_brl_sell"]:
            ext = "zip" if source == "b3" else "json"
            object_key = f"bronze/source={source}/reference_date={target}/raw.{ext}"
            response = s3.get_object(Bucket=args["bronze_bucket"], Key=object_key)
            with response["Body"] as body:
                payload = body.read(DOWNLOAD_LIMIT + 1)
            digest = hashlib.sha256(payload).hexdigest()
            if len(payload) > DOWNLOAD_LIMIT or digest != bronze["sources"][source]["sha256"]:
                raise ValueError("Bronze payload changed or exceeded size limit")
            payloads[source] = payload
        checked = validate_b3(payloads["b3"], target)
        rates = [parse_rate(payloads[n], target, n) for n in ["cdi", "selic", "usd_brl_sell"]]
        with zipfile.ZipFile(io.BytesIO(payloads["b3"])) as archive:
            lines = archive.read(archive.infolist()[0]).splitlines()[1:-1]
        context = GlueContext(SparkContext.getOrCreate())
        spark = context.spark_session
        job = Job(context)
        job.init(args["JOB_NAME"], args)
        quote_schema = T.StructType([
            T.StructField("trading_date", T.DateType(), False), T.StructField("ticker", T.StringType(), False),
            *[T.StructField(n, T.StringType(), True) for n in ["company_name", "specification", "currency", "isin"]],
            T.StructField("quotation_factor", T.IntegerType(), False), T.StructField("distribution_number", T.IntegerType(), False),
            *[T.StructField(n, T.DecimalType(13, 2), False) for n in ["open_raw", "high_raw", "low_raw", "close_raw"]],
            T.StructField("trades", T.IntegerType(), False), T.StructField("quantity", T.LongType(), False),
            T.StructField("volume", T.DecimalType(18, 2), False),
        ])
        rdd = spark.sparkContext.parallelize(lines, 2).map(lambda row: parse_quote(row, target)).filter(lambda row: row is not None)
        quotes = spark.createDataFrame(rdd, quote_schema).cache()
        if quotes.count() != checked["scope_rows"]:
            raise ValueError("Scoped count mismatch")
        # Remove exact duplicates only. Conflicting versions require investigation.
        unique = quotes.dropDuplicates().cache()
        if unique.groupBy("trading_date", "ticker").count().filter(F.col("count") > 1).limit(1).count():
            raise ValueError("Conflicting duplicate ticker/date")
        rate_schema = "trading_date date, series string, value decimal(20,10), unit string"
        rate_frame = spark.createDataFrame(rates, rate_schema)
        frames = [("b3_daily", unique, ["trading_date", "ticker"]), ("bcb_daily", rate_frame, ["trading_date", "series"])]
        counts = {}
        for name, frame, keys in frames:
            identifier = f"glue_catalog.{database}.{name}"
            frame.createOrReplaceTempView("incoming_silver")
            columns = ", ".join(f"{field.name} {field.dataType.simpleString()}" for field in frame.schema.fields)
            spark.sql(f"CREATE TABLE IF NOT EXISTS {identifier} ({columns}) USING iceberg PARTITIONED BY (months(trading_date)) LOCATION 's3://{args['silver_bucket']}/silver/{name}/' TBLPROPERTIES ('format-version'='2', 'write.format.default'='parquet')")
            on = " AND ".join(f"t.{k}=s.{k}" for k in keys)
            # Updating on retry is deterministic: input hashes are checked above.
            spark.sql(f"MERGE INTO {identifier} t USING incoming_silver s ON {on} WHEN MATCHED THEN UPDATE SET * WHEN NOT MATCHED THEN INSERT *")
            actual = spark.table(identifier).filter(F.col("trading_date") == F.lit(target)).cache()
            if actual.exceptAll(frame).limit(1).count() or frame.exceptAll(actual).limit(1).count():
                raise ValueError("Iceberg read-back differs from validated input")
            counts[name] = actual.count()
            actual.unpersist()
        job.commit()
        table.update_item(Key=key,
            UpdateExpression="SET #s=:success, row_counts=:counts, source_hashes=:hashes, updated_at=:now REMOVE lease_until",
            ConditionExpression="owner_id=:owner", ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":success": "SUCCESS", ":counts": counts, ":hashes": {n: hashlib.sha256(p).hexdigest() for n, p in payloads.items()}, ":now": int(time.time()), ":owner": owner})
        print(json.dumps({"stage": "silver", "reference_date": str(target), "status": "SUCCESS", "rows": counts}))
    except Exception as exc:
        table.update_item(Key=key,
            UpdateExpression="SET #s=:failed, error_type=:error, updated_at=:now REMOVE lease_until",
            ConditionExpression="owner_id=:owner", ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":failed": "FAILED", ":error": type(exc).__name__, ":now": int(time.time()), ":owner": owner})
        raise


if __name__ == "__main__":
    run()
