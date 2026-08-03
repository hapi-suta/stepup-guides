# Project 9 API container. The SAME image runs the web API and the worker;
# the command differs (see docker-compose.yml). Config is env-only at runtime -
# never baked into the image, never a secret in a layer.
FROM python:3.12-slim

WORKDIR /app

# Install deps first for better layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App code + templates + static assets.
COPY *.py ./
COPY templates ./templates
COPY static ./static

EXPOSE 8000

# Default command runs the API. docker-compose overrides it for the worker.
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
