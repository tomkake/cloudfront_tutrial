from fastapi import FastAPI, Request
from mangum import Mangum

app = FastAPI()


@app.get("/")
async def root(request: Request) -> dict[str, str | None]:
    return {
        "host": request.headers.get("x-viewer-host") or request.headers.get("host"),
        "origin_host": request.headers.get("host"),
    }


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


handler = Mangum(app)
