"""JSON logs on stdout, one object per line, so Loki/CloudWatch/kubectl logs | jq can read them."""
import json
import logging
import sys
from datetime import datetime, timezone

# attributes every LogRecord has; anything else on a record came from `extra=`
# (color_message is uvicorn's ANSI-coloured copy of msg)
_STANDARD = set(vars(logging.LogRecord("", 0, "", 0, "", None, None))) | {"message", "asctime", "taskName", "color_message"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": datetime.fromtimestamp(record.created, timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
        }
        for key, value in vars(record).items():
            if key not in _STANDARD and not key.startswith("_"):
                entry[key] = value
        if record.exc_info:
            entry["exc"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
    # uvicorn sets up its own plain-text handlers before it imports the app; send its
    # startup/error lines through the JSON handler instead
    for name in ("uvicorn", "uvicorn.error"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True
    # the request middleware in main.py writes the access log, so uvicorn's is dropped
    access = logging.getLogger("uvicorn.access")
    access.handlers = []
    access.propagate = False
