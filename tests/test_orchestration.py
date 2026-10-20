"""Offline simulation of the Step Functions definition. No AWS calls.

JSONata expressions are evaluated by jsonata-python; AWS integrations are faked
per state so the paths (success, rerun, holiday, failure and resume) are exercised.
"""
from pathlib import Path
import json
import re
import jsonata
import pytest

TEMPLATE = Path(__file__).resolve().parents[1] / "infra/modules/orchestration/pipeline.asl.json.tftpl"
ENTERED = "2026-10-20T21:00:00.000Z"
NOW = 1792530000


def render():
    text = TEMPLATE.read_text()
    text = text.replace("${jsonencode(subnets)}", '["subnet-1"]').replace("${jsonencode(security_groups)}", '["sg-1"]')
    values = {"table": "runs", "bronze_function_arn": "arn:bronze", "silver_job": "silver",
              "gold_cluster_arn": "arn:cluster", "gold_task_definition_arn": "arn:taskdef"}
    text = re.sub(r"\$\{(\w+)\}", lambda m: values[m.group(1)], text)
    assert "${" not in text and "%{" not in text
    return json.loads(text)


class StateError(Exception):
    def __init__(self, name):
        super().__init__(name)
        self.name = name


def evaluate(value, variables, states):
    if isinstance(value, dict):
        return {k: evaluate(v, variables, states) for k, v in value.items()}
    if isinstance(value, list):
        return [evaluate(v, variables, states) for v in value]
    if isinstance(value, str) and value.startswith("{%") and value.endswith("%}"):
        expr = jsonata.Jsonata(value[2:-2].strip())
        for name, bound in {**variables, "states": states}.items():
            expr.assign(name, bound)
        return expr.evaluate(None)
    return value


class World:
    def __init__(self):
        self.lock = {}
        self.items = {}
        self.calls = []
        self.bronze_error = None
        self.silver_error = None
        self.gold_result = {"TaskArn": "arn:task/1", "Containers": [{"ExitCode": 0}]}

    def status(self, pk):
        return self.items.get(pk, {}).get("status")

    def call(self, state, args, execution):
        self.calls.append(state)
        values = args.get("ExpressionAttributeValues", {})
        pk = args.get("Key", {}).get("pk", {}).get("S")
        if state == "AcquireLock":
            if self.lock.get("lease_until", 0) >= int(values[":now"]["N"]):
                raise StateError("DynamoDB.ConditionalCheckFailedException")
            self.lock = {"owner_id": values[":owner"]["S"], "lease_until": int(values[":lease"]["N"])}
            return {}
        if state in {"ReleaseLock", "ReleaseLockAfterFailure"}:
            if self.lock.get("owner_id") != values[":owner"]["S"]:
                raise StateError("DynamoDB.ConditionalCheckFailedException")
            self.lock.pop("lease_until", None)
            return {}
        if state == "Bronze":
            if self.bronze_error:
                raise StateError(self.bronze_error)
            payload = args["Payload"]
            return {"Payload": {"reference_date": payload.get("reference_date", "2026-10-20"), "status": "SUCCESS"}}
        if state in {"ReadPipelineStatus", "ReadSilverStatus"}:
            item = self.items.get(pk)
            return {"Item": {"status": {"S": item["status"]}}} if item else {}
        if state == "MarkRunning":
            self.items[pk] = {"status": "RUNNING", "execution": execution}
            return {}
        if state == "Silver":
            if self.silver_error:
                raise StateError(self.silver_error)
            self.items["silver#" + args["Arguments"]["--reference_date"]] = {"status": "SUCCESS"}
            return {"Id": "jr_1", "JobRunState": "SUCCEEDED"}
        if state == "Gold":
            assert args["LaunchType"] == "FARGATE" and args["NetworkConfiguration"]["AwsvpcConfiguration"]["AssignPublicIp"] == "ENABLED"
            return self.gold_result
        if state == "MarkSuccess":
            assert self.items[pk]["execution"] == values[":execution"]["S"]
            self.items[pk].update(status="SUCCESS", gold_task_arn=values[":task"]["S"])
            return {}
        if state == "PublishMarker":
            current = self.items.get(pk, {}).get("reference_date")
            if current and current > values[":date"]["S"]:
                raise StateError("DynamoDB.ConditionalCheckFailedException")
            self.items[pk] = {"reference_date": values[":date"]["S"]}
            return {}
        if state == "MarkFailed":
            self.items[pk] = {"status": "FAILED", "failed_step": values[":step"]["S"], "error_type": values[":error"]["S"]}
            return {}
        raise AssertionError(f"Unexpected task {state}")


def matches(rule, error):
    return "States.ALL" in rule["ErrorEquals"] or error in rule["ErrorEquals"]


def run(world, payload, execution="exec-1"):
    definition = render()
    variables, data = {}, payload
    name = definition["StartAt"]
    for _ in range(100):
        state = definition["States"][name]
        context = {"Execution": {"Name": execution}, "State": {"EnteredTime": ENTERED}}
        states = {"input": data, "context": context}
        kind = state["Type"]
        if kind == "Task":
            args = evaluate(state["Arguments"], variables, states)
            try:
                result = world.call(name, args, execution)
            except StateError as exc:
                rule = next(r for r in state.get("Catch", []) if matches(r, exc.name))
                error_states = {**states, "errorOutput": {"Error": exc.name, "Cause": "simulated"}}
                variables.update(evaluate(rule.get("Assign", {}), variables, error_states))
                name, data = rule["Next"], error_states["errorOutput"]
                continue
            states = {**states, "result": result}
            variables.update(evaluate(state.get("Assign", {}), variables, states))
            name, data = state["Next"], result
        elif kind == "Pass":
            variables.update(evaluate(state.get("Assign", {}), variables, states))
            name = state["Next"]
        elif kind == "Choice":
            name = next((c["Next"] for c in state["Choices"] if evaluate(c["Condition"], variables, states)), state["Default"])
        elif kind == "Succeed":
            return "SUCCEEDED", evaluate(state["Output"], variables, states)
        elif kind == "Fail":
            return "FAILED", evaluate(state["Error"], variables, states)
    raise AssertionError("State machine did not terminate")


def test_definition_is_bounded_and_every_transition_exists():
    definition = render()
    names = set(definition["States"])
    assert definition["TimeoutSeconds"] == 3600 and definition["QueryLanguage"] == "JSONata"
    targets = {definition["StartAt"]}
    for name, state in definition["States"].items():
        targets |= {state[k] for k in ("Next", "Default") if k in state}
        targets |= {c["Next"] for c in state.get("Choices", []) + state.get("Catch", [])}
        if state["Type"] == "Task":
            assert 0 < state["TimeoutSeconds"] <= 1800, name
            assert any("States.ALL" in c["ErrorEquals"] for c in state.get("Catch", [])) or name == "AcquireLock", name
            assert sum(r["MaxAttempts"] for r in state.get("Retry", [])) <= 3, name
    assert targets <= names and names <= targets
    # Paid compute is never retried automatically.
    assert "Retry" not in definition["States"]["Silver"] and "Retry" not in definition["States"]["Gold"]


def test_success_publishes_once_and_rerun_skips_paid_steps():
    world = World()
    assert run(world, {"reference_date": "2026-10-19"}) == ("SUCCEEDED", {"status": "PUBLISHED", "reference_date": "2026-10-19"})
    assert world.status("pipeline#2026-10-19") == "SUCCESS" and world.items["pipeline#published"]["reference_date"] == "2026-10-19"
    assert "lease_until" not in world.lock
    world.calls.clear()
    assert run(world, {"reference_date": "2026-10-19"}, "exec-2")[1]["status"] == "ALREADY_PUBLISHED"
    assert "Silver" not in world.calls and "Gold" not in world.calls
    world.calls.clear()
    assert run(world, {"reference_date": "2026-10-19", "force": True}, "exec-3")[1]["status"] == "PUBLISHED"
    assert "Silver" in world.calls and "Gold" in world.calls


def test_older_date_never_moves_publication_marker_backwards():
    world = World()
    run(world, {"reference_date": "2026-10-19"})
    assert run(world, {"reference_date": "2026-10-16"}, "exec-2")[0] == "SUCCEEDED"
    assert world.items["pipeline#published"]["reference_date"] == "2026-10-19"


def test_holiday_is_explicit_and_not_an_empty_load():
    world = World()
    world.bronze_error = "SourceNotAvailable"
    assert run(world, {"scheduled_time": "2026-10-12T21:00:00Z"}) == ("SUCCEEDED", {"status": "SOURCE_UNAVAILABLE", "reference_date": ""})
    assert not world.items and "lease_until" not in world.lock


def test_gold_failure_blocks_publication_and_retry_resumes_without_silver():
    world = World()
    world.gold_result = {"TaskArn": "arn:task/1", "Containers": [{"ExitCode": 2}]}
    assert run(world, {"reference_date": "2026-10-19"}) == ("FAILED", "PipelineFailed.gold")
    assert world.items["pipeline#2026-10-19"] == {"status": "FAILED", "failed_step": "gold", "error_type": "NonZeroExit.2"}
    assert "pipeline#published" not in world.items and "lease_until" not in world.lock
    world.calls.clear()
    world.gold_result = {"TaskArn": "arn:task/2", "Containers": [{"ExitCode": 0}]}
    assert run(world, {"reference_date": "2026-10-19"}, "exec-2")[1]["status"] == "PUBLISHED"
    assert "Silver" not in world.calls and "Gold" in world.calls


def test_missing_exit_code_fails_closed():
    world = World()
    world.gold_result = {"TaskArn": "arn:task/1"}
    assert run(world, {"reference_date": "2026-10-19"}) == ("FAILED", "PipelineFailed.gold")


def test_silver_failure_stops_before_gold():
    world = World()
    world.silver_error = "Glue.AWSGlueException"
    assert run(world, {"reference_date": "2026-10-19"}) == ("FAILED", "PipelineFailed.silver")
    assert "Gold" not in world.calls and world.items["pipeline#2026-10-19"]["error_type"] == "Glue.AWSGlueException"


@pytest.mark.parametrize("error", ["ValueError", "States.Timeout"])
def test_bronze_failure_without_date_releases_lock(error):
    world = World()
    world.bronze_error = error
    assert run(world, {"scheduled_time": "2026-10-20T21:00:00Z"}) == ("FAILED", "PipelineFailed.bronze")
    assert not world.items and "lease_until" not in world.lock


def test_concurrent_execution_is_rejected_before_any_work():
    world = World()
    world.lock = {"owner_id": "other", "lease_until": NOW + 3600}
    assert run(world, {"reference_date": "2026-10-19"}) == ("FAILED", "PipelineBusy")
    assert world.calls == ["AcquireLock"]


def test_expired_lease_from_interrupted_execution_is_recovered():
    world = World()
    world.lock = {"owner_id": "aborted", "lease_until": NOW - 7200}
    assert run(world, {"reference_date": "2026-10-19"})[0] == "SUCCEEDED"
