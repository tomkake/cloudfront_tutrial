import json
import logging
import os

import boto3
from fastapi import FastAPI, Request
from mangum import Mangum

app = FastAPI()
logger = logging.getLogger()
logger.setLevel(logging.INFO)
lambda_client = boto3.client("lambda")

LAMBDA_ROLE = os.environ.get("LAMBDA_ROLE", "primary")
DOWNSTREAM_FUNCTION_NAME = os.environ.get("DOWNSTREAM_FUNCTION_NAME")
VIEWER_HOST_HEADER = os.environ.get("VIEWER_HOST_HEADER", "x-viewer-host")


def log_request_source(message: str, **fields: str | None) -> None:
    logger.info(json.dumps({"message": message, **fields}, ensure_ascii=False))


@app.get("/")
async def root(request: Request) -> dict[str, object | None]:
    viewer_host = request.headers.get(VIEWER_HOST_HEADER)
    origin_host = request.headers.get("host")
    requested_from = "cloudfront" if viewer_host else "unknown"

    log_request_source(
        "primary lambda request received",
        lambda_role=LAMBDA_ROLE,
        requested_from=requested_from,
        viewer_host=viewer_host,
        origin_host=origin_host,
    )

    downstream_response = None
    if DOWNSTREAM_FUNCTION_NAME:
        payload = {
            "invoked_by": os.environ.get("AWS_LAMBDA_FUNCTION_NAME"),
            "requested_from": os.environ.get("AWS_LAMBDA_FUNCTION_NAME"),
            "upstream_request_source": requested_from,
            "viewer_host": viewer_host,
            "origin_host": origin_host,
        }
        response = lambda_client.invoke(
            FunctionName=DOWNSTREAM_FUNCTION_NAME,
            InvocationType="RequestResponse",
            Payload=json.dumps(payload).encode("utf-8"),
        )
        downstream_response = json.loads(response["Payload"].read().decode("utf-8"))

    return {
        "host": viewer_host or origin_host,
        "origin_host": origin_host,
        "requested_from": requested_from,
        "downstream": downstream_response,
    }


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


http_handler = Mangum(app)


def handler(event: dict, context: object) -> dict:
    if LAMBDA_ROLE == "secondary":
        requested_from = event.get("requested_from") or event.get("invoked_by")
        log_request_source(
            "secondary lambda request received",
            lambda_role=LAMBDA_ROLE,
            requested_from=requested_from,
            invoked_by=event.get("invoked_by"),
            upstream_request_source=event.get("upstream_request_source"),
            viewer_host=event.get("viewer_host"),
            origin_host=event.get("origin_host"),
        )
        return {
            "lambda_role": LAMBDA_ROLE,
            "requested_from": requested_from,
            "invoked_by": event.get("invoked_by"),
            "upstream_request_source": event.get("upstream_request_source"),
        }

    return http_handler(event, context)
