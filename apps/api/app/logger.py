import logging


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
