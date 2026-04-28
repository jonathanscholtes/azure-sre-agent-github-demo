import logging
import traceback
from typing import Any


def configure_logging(name: str = "api"):
    """Configure logging to reuse gunicorn handlers when available."""
    gunicorn_logger = logging.getLogger("gunicorn.error")
    logger = logging.getLogger(name)
    if gunicorn_logger.handlers:
        logger.handlers = gunicorn_logger.handlers
        logger.setLevel(gunicorn_logger.level)
    if logger.level > logging.INFO:
        logger.setLevel(logging.INFO)
    return logger


def log_exception(
    logger: logging.Logger,
    message: str,
    exc: Exception,
    **context: Any,
) -> None:
    """Log an exception with structured business context.

    Callers pass key/value pairs that help a coding agent reproduce the failure
    (order_id, customer_id, operation, etc.). These land in App Insights
    customDimensions alongside the full stack trace.

    The caller is responsible for re-raising after calling this function.

    Usage::

        try:
            ...
        except Exception as exc:
            log_exception(logger, "Failed to process order", exc,
                          operation="process_order",
                          order_id=order_id,
                          line_item_count=len(items))
            raise
    """
    extra = {
        "exception_type": type(exc).__qualname__,
        "exception_module": type(exc).__module__,
        "exception_message": str(exc),
        "stack_trace": traceback.format_exc(),
        **context,
    }
    logger.exception("%s: %s", message, exc, extra=extra)
