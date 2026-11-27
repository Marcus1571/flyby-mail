FROM python:3.12-slim
RUN useradd --system --uid 10001 flyby && mkdir /data && chown flyby /data
COPY server.py /app/server.py
USER flyby
WORKDIR /app
EXPOSE 8787
CMD ["python", "-u", "server.py"]
