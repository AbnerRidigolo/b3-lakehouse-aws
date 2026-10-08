"""Single-year Spark backfill for EMR or Glue; no worker internet downloads."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid


def options(argv):
    parser = argparse.ArgumentParser()
    for name in ['year','bronze_bucket','silver_bucket','runs_table','database']: parser.add_argument('--'+name, required=True)
    parser.add_argument('--engine', choices=['emr','glue'], default='emr')
    result, unknown = parser.parse_known_args(argv)
    if unknown and result.engine != 'glue': parser.error('Unexpected EMR arguments')
    return result


def run():
    # spark.archives extracts the pinned pure-Python SDK into the working directory.
    sys.path.insert(0, str(Path('sdk').resolve()))
    import boto3
    from pyspark.sql import SparkSession, functions as F
    from src.silver.transform import parse_quote, safe_identifier
    # Glue injects framework arguments such as JOB_NAME. Data parameters remain
    # mandatory; Glue pins destinations and engine; year is explicitly selected.
    a = options(sys.argv[1:])
    if not a.year.isdigit() or not 1986 <= int(a.year) <= 2025:
        raise ValueError('Only complete historical years 1986-2025 are supported')
    year = int(a.year); database = safe_identifier(a.database)
    s3 = boto3.client('s3'); table = boto3.resource('dynamodb').Table(a.runs_table)
    source = table.get_item(Key={'pk':f'bronze#year={year}'}, ConsistentRead=True).get('Item',{})
    if source.get('status') != 'SUCCESS': raise ValueError('Historical bronze is not SUCCESS')
    prefix = f'bronze/history/year={year}/'
    response = s3.get_object(Bucket=a.bronze_bucket, Key=prefix+'manifest.json')
    with response['Body'] as body: payload = body.read(1024 * 1024 + 1)
    if len(payload) > 1024 * 1024 or hashlib.sha256(payload).hexdigest() != source['manifest_sha256']:
        raise ValueError('Untrusted historical manifest')
    manifest = json.loads(payload)
    if manifest['year'] != year or manifest['version'] != 1: raise ValueError('Invalid manifest year/version')
    if manifest.get('source_scoped_rows', manifest['scoped_rows']) != manifest['scoped_rows'] + manifest.get('quarantined_rows', 0):
        raise ValueError('Quarantine reconciliation failed')
    key, owner, now = {'pk':f'history#{year}'}, uuid.uuid4().hex, int(time.time())
    table.update_item(Key=key, UpdateExpression='SET #s=:running, owner_id=:owner, lease_until=:lease, updated_at=:now, expires_at=:expiry',
        ConditionExpression='attribute_not_exists(lease_until) OR lease_until < :now', ExpressionAttributeNames={'#s':'status'},
        ExpressionAttributeValues={':running':'RUNNING',':owner':owner,':lease':now+1200,':now':now,':expiry':now+90*86400})
    try:
        names = set()
        for file in manifest['files']:
            name = file['name']
            if Path(name).name != name or name in names: raise ValueError('Unsafe or duplicate manifest object')
            names.add(name); h=hashlib.sha256(); size=0
            response=s3.get_object(Bucket=a.bronze_bucket,Key=prefix+name)
            with response['Body'] as body:
                for chunk in iter(lambda: body.read(1024*1024),b''):
                    h.update(chunk);size+=len(chunk)
                    if size>file['bytes']: raise ValueError('Input size changed')
            if size!=file['bytes'] or h.hexdigest()!=file['sha256']: raise ValueError('Historical input checksum mismatch')
        quote_names=sorted(n for n in names if n.startswith('quotes-') and n.endswith('.txt'))
        if not quote_names or 'rates.jsonl' not in names: raise ValueError('Missing prepared inputs')
        spark=SparkSession.builder.getOrCreate()
        def parse(line):
            row=line.encode('latin-1');day=datetime.strptime(row[2:10].decode(),'%Y%m%d').date()
            if day.year!=year: raise ValueError('Row outside requested year')
            result=parse_quote(row,day)
            if result is None: raise ValueError('Unexpected out-of-scope prepared record')
            return result
        schema='trading_date date, ticker string, company_name string, specification string, currency string, isin string, quotation_factor int, distribution_number int, open_raw decimal(13,2), high_raw decimal(13,2), low_raw decimal(13,2), close_raw decimal(13,2), trades int, quantity bigint, volume decimal(18,2)'
        text=spark.read.text([f's3://{a.bronze_bucket}/{prefix}{n}' for n in quote_names])
        quotes=spark.createDataFrame(text.rdd.map(lambda row:parse(row.value)),schema).cache()
        if quotes.count()!=manifest['scoped_rows']: raise ValueError('Scoped annual count mismatch')
        unique=quotes.dropDuplicates().cache()
        if unique.groupBy('trading_date','ticker').count().filter('count > 1').limit(1).count(): raise ValueError('Conflicting annual duplicate')
        rates=spark.read.schema('trading_date string, series string, value string, unit string').json(f's3://{a.bronze_bucket}/{prefix}rates.jsonl')
        rates=rates.withColumn('trading_date',F.to_date('trading_date')).withColumn('value',F.col('value').cast('decimal(20,10)')).cache()
        if rates.count()!=manifest['rate_rows'] or rates.filter(F.col('value').isNull() | F.col('trading_date').isNull() | (F.year('trading_date')!=year)).limit(1).count(): raise ValueError('Invalid annual rates')
        if rates.groupBy('trading_date','series').count().filter('count > 1').limit(1).count(): raise ValueError('Duplicate rates')
        counts={}
        for name,frame,keys in [('b3_daily',unique,['trading_date','ticker']),('bcb_daily',rates,['trading_date','series'])]:
            target=f'glue_catalog.{database}.{name}'
            # Daily Glue has already created both tables. Do not silently change schema.
            spark.table(target)
            frame.createOrReplaceTempView('incoming_history')
            on=' AND '.join(f't.{k}=s.{k}' for k in keys)
            spark.sql(f'MERGE INTO {target} t USING incoming_history s ON {on} WHEN MATCHED THEN UPDATE SET * WHEN NOT MATCHED THEN INSERT *')
            actual=spark.table(target).filter(F.year('trading_date')==year).cache()
            if actual.exceptAll(frame).limit(1).count() or frame.exceptAll(actual).limit(1).count(): raise ValueError('Annual Iceberg read-back differs')
            counts[name]=actual.count();actual.unpersist()
        table.update_item(Key=key,UpdateExpression='SET #s=:success, row_counts=:counts, quarantined_rows=:quarantined, manifest_sha256=:hash, updated_at=:now REMOVE lease_until',ConditionExpression='owner_id=:owner',ExpressionAttributeNames={'#s':'status'},ExpressionAttributeValues={':success':'SUCCESS',':counts':counts,':quarantined':manifest.get('quarantined_rows',0),':hash':source['manifest_sha256'],':now':int(time.time()),':owner':owner})
        print(json.dumps({'year':year,'status':'SUCCESS','rows':counts}))
    except Exception as exc:
        table.update_item(Key=key,UpdateExpression='SET #s=:failed, error_type=:error, updated_at=:now REMOVE lease_until',ConditionExpression='owner_id=:owner',ExpressionAttributeNames={'#s':'status'},ExpressionAttributeValues={':failed':'FAILED',':error':type(exc).__name__,':now':int(time.time()),':owner':owner})
        raise


if __name__=='__main__':run()
