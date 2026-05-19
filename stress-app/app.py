from flask import Flask, render_template, jsonify
import threading
import time
import math
import os
import logging

# ─── Azure Application Insights ────────────────────────────────────────────────
# Set APPINSIGHTS_CONNECTION_STRING as environment variable on the VM:
#   export APPINSIGHTS_CONNECTION_STRING="InstrumentationKey=xxx;IngestionEndpoint=..."
#
# Install deps:  pip3 install opencensus-ext-azure opencensus-ext-flask

APPINSIGHTS_CONNECTION_STRING = os.environ.get("APPINSIGHTS_CONNECTION_STRING", "")

ai_logger = logging.getLogger("app_insights")

if APPINSIGHTS_CONNECTION_STRING:
    try:
        from opencensus.ext.azure.log_exporter import AzureLogHandler
        from opencensus.ext.azure import metrics_exporter
        from opencensus.ext.flask import FlaskMiddleware
        from opencensus.trace.samplers import ProbabilitySampler

        # ── Structured logger → App Insights (traces + customEvents) ──
        handler = AzureLogHandler(connection_string=APPINSIGHTS_CONNECTION_STRING)
        handler.setLevel(logging.DEBUG)
        ai_logger.addHandler(handler)
        ai_logger.setLevel(logging.DEBUG)

        AI_ENABLED = True
        print("[AppInsights] Handler attached — logs will flow to Azure.")
    except ImportError:
        AI_ENABLED = False
        print("[AppInsights] opencensus-ext-azure not installed. Logs stay local.")
else:
    AI_ENABLED = False
    print("[AppInsights] No connection string set — running without Azure logging.")

# Always also log to stdout (visible in VM journal / Azure serial log)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
std_logger = logging.getLogger("stress_app")


def track_event(name: str, properties: dict = None):
    """
    Send a customEvent to App Insights + a matching INFO trace.
    properties dict becomes searchable dimensions in App Insights.
    """
    props = properties or {}
    std_logger.info("[EVENT] %s | %s", name, props)
    if AI_ENABLED:
        # opencensus represents customEvents as log records with
        # extra={'custom_dimensions': {...}}
        ai_logger.info(
            name,
            extra={"custom_dimensions": {"event_name": name, **props}},
        )


def track_metric(name: str, value: float, properties: dict = None):
    """Send a numeric measurement as a trace (App Insights custom metric)."""
    props = properties or {}
    std_logger.info("[METRIC] %s=%.2f | %s", name, value, props)
    if AI_ENABLED:
        ai_logger.info(
            "metric",
            extra={"custom_dimensions": {"metric_name": name, "value": str(value), **props}},
        )


def track_exception(exc: Exception, properties: dict = None):
    """Log an exception to App Insights exceptions table."""
    props = properties or {}
    std_logger.exception("[EXCEPTION] %s | %s", exc, props)
    if AI_ENABLED:
        ai_logger.exception(
            str(exc),
            extra={"custom_dimensions": props},
        )


# ───────────────────────────────────────────────────────────────────────────────

app = Flask(__name__)

# Attach Flask middleware for automatic request telemetry (if available)
if AI_ENABLED:
    try:
        from opencensus.ext.flask import FlaskMiddleware
        from opencensus.trace.samplers import ProbabilitySampler
        FlaskMiddleware(
            app,
            sampler=ProbabilitySampler(rate=1.0),
            exporter=__import__(
                "opencensus.ext.azure.trace_exporter",
                fromlist=["AzureExporter"]
            ).AzureExporter(connection_string=APPINSIGHTS_CONNECTION_STRING),
        )
    except Exception as e:
        std_logger.warning("Could not attach FlaskMiddleware: %s", e)

# Track active stress threads
active_threads = {}
stop_flags = {}

# ─── CPU stress functions ───────────────────────────────────────────────

def cpu_stress_worker(level, stop_event):
    """Burn CPU cycles based on level: high=100%, med=50%, low=20%"""
    duty_cycles = {"high": 1.0, "med": 0.5, "low": 0.2}
    duty = duty_cycles.get(level, 0.5)

    while not stop_event.is_set():
        end = time.time() + duty
        while time.time() < end:
            # Pure CPU burn
            _ = math.sqrt(123456789.123) * math.log(987654321.987)
        time.sleep(1.0 - duty)

def start_cpu_stress(level):
    stop_cpu_stress()
    n_threads = {"high": os.cpu_count(), "med": max(1, os.cpu_count() // 2), "low": 1}
    count = n_threads.get(level, 1)
    stop_event = threading.Event()
    stop_flags["cpu"] = stop_event
    threads = []
    for _ in range(count):
        t = threading.Thread(target=cpu_stress_worker, args=(level, stop_event), daemon=True)
        t.start()
        threads.append(t)
    active_threads["cpu"] = threads

def stop_cpu_stress():
    if "cpu" in stop_flags:
        stop_flags["cpu"].set()
        del stop_flags["cpu"]
    active_threads.pop("cpu", None)

# ─── RAM stress functions ───────────────────────────────────────────────

RAM_BLOCKS = []
RAM_LOCK = threading.Lock()

def start_ram_stress(level):
    stop_ram_stress()
    targets = {"high": 0.75, "med": 0.40, "low": 0.15}
    fraction = targets.get(level, 0.4)

    total = get_total_ram()
    target_bytes = int(total * fraction)
    chunk = 50 * 1024 * 1024  # 50 MB chunks

    def allocate():
        allocated = 0
        with RAM_LOCK:
            while allocated < target_bytes:
                try:
                    RAM_BLOCKS.append(bytearray(min(chunk, target_bytes - allocated)))
                    allocated += chunk
                except MemoryError:
                    break

    t = threading.Thread(target=allocate, daemon=True)
    t.start()
    active_threads["ram"] = [t]

def stop_ram_stress():
    with RAM_LOCK:
        RAM_BLOCKS.clear()
    active_threads.pop("ram", None)

def get_total_ram():
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal"):
                    return int(line.split()[1]) * 1024
    except Exception:
        return 2 * 1024 * 1024 * 1024  # fallback 2GB
    return 2 * 1024 * 1024 * 1024

def get_mem_usage():
    try:
        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":")[0], line.split(":")[1].strip().split()[0]
                info[k] = int(v)
        total = info["MemTotal"]
        available = info["MemAvailable"]
        used = total - available
        return round(used / total * 100, 1)
    except Exception:
        return 0

def get_cpu_usage():
    try:
        with open("/proc/stat") as f:
            line = f.readline()
        fields = list(map(int, line.strip().split()[1:]))
        idle = fields[3]
        total = sum(fields)
        time.sleep(0.3)
        with open("/proc/stat") as f:
            line = f.readline()
        fields2 = list(map(int, line.strip().split()[1:]))
        idle2 = fields2[3]
        total2 = sum(fields2)
        d_idle = idle2 - idle
        d_total = total2 - total
        return round((1 - d_idle / d_total) * 100, 1) if d_total else 0
    except Exception:
        return 0

# ─── Routes ────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/stress/cpu/<level>", methods=["POST"])
def stress_cpu(level):
    if level not in ("high", "med", "low", "stop"):
        return jsonify({"error": "invalid level"}), 400
    if level == "stop":
        stop_cpu_stress()
        return jsonify({"status": "CPU stress stopped"})
    start_cpu_stress(level)
    return jsonify({"status": f"CPU stress started: {level}"})

@app.route("/api/stress/ram/<level>", methods=["POST"])
def stress_ram(level):
    if level not in ("high", "med", "low", "stop"):
        return jsonify({"error": "invalid level"}), 400
    if level == "stop":
        stop_ram_stress()
        return jsonify({"status": "RAM stress stopped"})
    start_ram_stress(level)
    return jsonify({"status": f"RAM stress started: {level}"})

@app.route("/api/status")
def status():
    return jsonify({
        "cpu_percent": get_cpu_usage(),
        "mem_percent": get_mem_usage(),
        "cpu_active": "cpu" in stop_flags,
        "ram_active": len(RAM_BLOCKS) > 0,
    })

@app.route("/api/stop/all", methods=["POST"])
def stop_all():
    stop_cpu_stress()
    stop_ram_stress()
    return jsonify({"status": "All stress stopped"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)