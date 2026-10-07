"""Generate a bounded EMR request locally. Does NOT call StartJobRun."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def request(application_id, account_id, manifest_sha):
    if not re.fullmatch('[a-z0-9]{1,64}',application_id) or not re.fullmatch('[0-9]{12}',account_id) or not re.fullmatch('[a-f0-9]{64}',manifest_sha): raise ValueError('Invalid request identifiers')
    bronze=f'b3-lakehouse-aws-bronze-{account_id}';silver=f'b3-lakehouse-aws-silver-{account_id}'
    conf={
        'spark.driver.cores':'2','spark.driver.memory':'6g','spark.executor.cores':'2','spark.executor.memory':'6g',
        'spark.executor.instances':'1','spark.dynamicAllocation.enabled':'false','spark.sql.shuffle.partitions':'2',
        'spark.emr-serverless.driver.disk':'20G','spark.emr-serverless.executor.disk':'20G',
        'spark.archives':f's3://{silver}/scripts/history-sdk.zip#sdk',
        'spark.submit.pyFiles':f's3://{silver}/scripts/history-libs.zip',
        'spark.jars':'/usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar',
        'spark.sql.extensions':'org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions',
        'spark.sql.catalog.glue_catalog':'org.apache.iceberg.spark.SparkCatalog',
        'spark.sql.catalog.glue_catalog.catalog-impl':'org.apache.iceberg.aws.glue.GlueCatalog',
        'spark.sql.catalog.glue_catalog.io-impl':'org.apache.iceberg.aws.s3.S3FileIO',
        'spark.sql.catalog.glue_catalog.warehouse':f's3://{silver}/silver/',
        'spark.sql.catalog.glue_catalog.s3.sse.type':'s3'}
    return {'applicationId':application_id,'executionRoleArn':f'arn:aws:iam::{account_id}:role/b3-lakehouse-aws-history-2025',
        'clientToken':hashlib.sha256((application_id+manifest_sha).encode()).hexdigest(),'name':'backfill-2025',
        'executionTimeoutMinutes':15,'retryPolicy':{'maxAttempts':1},
        'jobDriver':{'sparkSubmit':{'entryPoint':f's3://{silver}/scripts/history-job.py',
            'entryPointArguments':['--year','2025','--bronze_bucket',bronze,'--silver_bucket',silver,'--runs_table','b3-lakehouse-aws-bronze-runs','--database','b3_lakehouse_silver'],
            'sparkSubmitParameters':' '.join('--conf '+k+'='+v for k,v in conf.items())}},
        'configurationOverrides':{'monitoringConfiguration':{'managedPersistenceMonitoringConfiguration':{'enabled':False},'s3MonitoringConfiguration':{'logUri':f's3://{silver}/history-logs/'}}},
        'tags':{'Project':'b3-lakehouse-aws','Component':'history-2025'}}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--application-id',required=True);p.add_argument('--account-id',required=True);p.add_argument('--manifest-sha',required=True);a=p.parse_args()
    out=Path('local/emr-2025-request.json');out.parent.mkdir(exist_ok=True);out.write_text(json.dumps(request(a.application_id,a.account_id,a.manifest_sha),indent=2)+'\n',encoding='utf-8');print(str(out))
