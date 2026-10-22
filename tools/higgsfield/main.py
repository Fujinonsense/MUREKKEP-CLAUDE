"""Seedance 2.5 text-to-video through the official Higgsfield SDK. Makes one billable request and
prints the video's URL only when the request completed; a failed, cancelled or moderated (NSFW)
request is reported as such. The key comes from .env.local (see set_key.py).

    uv run --with-requirements tools/higgsfield/requirements.txt python tools/higgsfield/main.py
"""
import sys

import higgsfield_client

from env import load_key

MODEL = "bytedance/seedance-2.5/text-to-video"
ARGUMENTS = {
    "prompt": "A cinematic scene at sunset",
    "duration": 5,
    "resolution": "720p",
    "aspect_ratio": "16:9",
}


def video_url(result: dict):
    """The URL in the result's "video" field, whether it is a string, an object or a list."""
    video = result.get("video")
    if isinstance(video, list):
        video = video[0] if video else None
    if isinstance(video, dict):
        video = video.get("url")
    return video if isinstance(video, str) and video.startswith("http") else None


def main() -> int:
    if not load_key():
        print("HF_KEY is not set: save the key first with tools/higgsfield/set_key.py.")
        return 2
    try:
        result = higgsfield_client.subscribe(
            MODEL,
            arguments=ARGUMENTS,
            on_enqueue=lambda request_id: print(f"enqueued: {request_id}", flush=True),
            on_queue_update=lambda status: print(f"status: {type(status).__name__}", flush=True),
        )
    except Exception as error:  # noqa: BLE001 — report any SDK or HTTP failure, never success
        print(f"request failed: {type(error).__name__}: {error}")
        return 1
    status = result.get("status")
    if status != "completed":
        detail = result.get("error") or result.get("message") or ""
        print(f"not completed: status={status} {detail}".strip())
        return 1
    url = video_url(result)
    if url is None:
        print(f"completed, but the response has no video URL (fields: {sorted(result)})")
        return 1
    print(url)
    return 0


if __name__ == "__main__":
    sys.exit(main())
