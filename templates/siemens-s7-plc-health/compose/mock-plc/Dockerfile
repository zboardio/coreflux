# A mock PLC for the health kit: a python-snap7 server holding DB880..DB882 and running the kit's algorithm.
# It proves the broker side, never a CPU.
FROM python:3.12-slim
RUN pip install --no-cache-dir --root-user-action=ignore python-snap7==3.3.1
ENV PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY kit_layout.py kit_mock.py ./
EXPOSE 102
CMD ["python", "-u", "kit_mock.py", "--family", "s7-300"]
