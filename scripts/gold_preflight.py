"""Read-only preflight, intended for the authenticated AWS CloudShell.

Does not export credentials, run Athena queries, start jobs or create resources.
"""
import json
import boto3
from botocore.exceptions import ClientError


def main():
    session = boto3.Session(region_name='us-east-1')
    account = session.client('sts').get_caller_identity()['Account']
    if account != '259081046223':
        raise RuntimeError('Unexpected account; stopping')
    report = {'account': account, 'region': 'us-east-1'}
    for name, operation in {
        'account_plan': lambda: session.client('freetier').get_account_plan(),
        'budgets': lambda: session.client('budgets').describe_budgets(AccountId=account),
        'ecs_service_role': lambda: session.client('iam').get_role(RoleName='AWSServiceRoleForECS'),
        'ecs_clusters': lambda: session.client('ecs').list_clusters(maxResults=10),
        'ecr_repositories': lambda: session.client('ecr').describe_repositories(repositoryNames=['b3-lakehouse-aws-gold']),
    }.items():
        try:
            response = operation()
            response.pop('ResponseMetadata', None)
            if name == 'ecs_service_role':
                response = {'exists': True}
            if name == 'budgets':
                response = [{'name': b['BudgetName'], 'calculated_spend': b.get('CalculatedSpend'),
                             'last_updated': b.get('LastUpdatedTime')} for b in response.get('Budgets', [])]
            report[name] = response
        except ClientError as exc:
            report[name] = {'error': exc.response['Error']['Code']}
    print(json.dumps(report, default=str, indent=2))


if __name__ == '__main__':
    main()
