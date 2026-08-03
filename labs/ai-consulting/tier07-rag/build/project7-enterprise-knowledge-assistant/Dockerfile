# Project 7 container. Runs the FastAPI service.
# Database connection + ANTHROPIC_API_KEY are passed as environment variables
# at run time - never baked into the image.
FROM python:3.12-slim

WORKDIR /app

# Install deps first for better layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App code.
COPY rag.py app.py ./

EXPOSE 8000

# Config comes entirely from the environment (12-factor).
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
