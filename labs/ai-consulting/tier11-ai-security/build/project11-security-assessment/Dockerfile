# Mock vulnerable knowledge assistant - runs with the local mock LLM by default.
# To use the real Claude API, pass -e ANTHROPIC_API_KEY=... at run time.
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
