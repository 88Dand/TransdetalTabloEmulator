#!/bin/bash

set -e

APP_DIR="/opt/parking-board"
SERVICE_NAME="parking-board"
PORT="8090"

echo "======================================="
echo " Parking Board Emulator Installation"
echo "======================================="

# --- root check ---
if [ "$EUID" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi

# --- install packages ---
echo "[1/8] Installing system packages..."

apt update

DEBIAN_FRONTEND=noninteractive apt install -y \
    python3 \
    python3-venv \
    python3-full \
    curl

# --- create app dir ---
echo "[2/8] Creating application directory..."

mkdir -p ${APP_DIR}

cd ${APP_DIR}

# --- create venv ---
echo "[3/8] Creating virtual environment..."

python3 -m venv venv

source venv/bin/activate

# --- install python packages ---
echo "[4/8] Installing Python packages..."

pip install --upgrade pip
pip install fastapi "uvicorn[standard]"

# --- create app.py ---
echo "[5/8] Creating backend..."

cat > ${APP_DIR}/app.py << 'EOF'
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect, Response
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from typing import Dict
import json
import os

app = FastAPI()

STATE_FILE = "state.json"

current_state: Dict = {}
last_status: int = 0

clients = []

VALID_IMAGES = {
    "car", "ecar", "moto", "2car",
    "arrow_up", "arrow_down", "arrow_left", "arrow_right"
}

def load_state():
    global current_state, last_status
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                data = json.load(f)
                current_state = data.get("data", {})
                last_status = data.get("status", 0)
        except:
            current_state = {}
            last_status = 0

def save_state():
    with open(STATE_FILE, "w") as f:
        json.dump({
            "data": current_state,
            "status": last_status
        }, f)

load_state()

def validate_payload(data):
    required = ["type", "version", "datetime", "pattern"]

    for field in required:
        if field not in data:
            return False, {
                "type": 5,
                "version": 6,
                "datetime": 7,
                "pattern": 8
            }.get(field, 4)

    if data["pattern"] not in [0, 1, 2]:
        return False, 10

    for i in range(1, 6):
        key = f"str{i}"

        if key not in data:
            continue

        row = data[key]

        if "img" in row and row["img"] not in VALID_IMAGES:
            row.pop("img")

        if "text" in row:
            try:
                int(row["text"])
            except:
                return False, 4

    return True, 0

def build_response(status: int) -> Response:
    body = json.dumps({"status": status})

    headers = {
        "Content-Length": str(len(body.encode("utf-8"))),
        "Connection": "close",
        "Server": "Board"
    }

    return Response(
        content=body,
        status_code=200,
        media_type="application/json",
        headers=headers
    )

async def broadcast():
    payload = {
        "data": current_state,
        "status": last_status
    }

    for ws in clients:
        try:
            await ws.send_json(payload)
        except:
            pass

@app.get("/it.php")
async def get_data():
    return JSONResponse(content=current_state)

@app.post("/places")
async def post_places(request: Request):
    global current_state, last_status

    raw_body = await request.body()

    cl = request.headers.get("content-length")

    if cl is None:
        last_status = 2
        save_state()
        await broadcast()
        return build_response(last_status)

    try:
        cl = int(cl)
    except:
        last_status = 2
        save_state()
        await broadcast()
        return build_response(last_status)

    if cl != len(raw_body):
        last_status = 2
        save_state()
        await broadcast()
        return build_response(last_status)

    try:
        data = json.loads(raw_body.decode("utf-8"))
    except:
        last_status = 4
        save_state()
        await broadcast()
        return build_response(last_status)

    ok, status = validate_payload(data)

    if not ok:
        last_status = status
        save_state()
        await broadcast()
        return build_response(last_status)

    current_state = data
    last_status = 0

    save_state()

    await broadcast()

    return build_response(0)

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()

    clients.append(ws)

    await ws.send_json({
        "data": current_state,
        "status": last_status
    })

    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        clients.remove(ws)

@app.get("/")
async def ui():
    with open("index.html", "r") as f:
        return HTMLResponse(f.read())

app.mount("/static", StaticFiles(directory="."), name="static")
EOF

# --- create index.html ---
echo "[6/8] Creating frontend..."

cat > ${APP_DIR}/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Parking Board Emulator</title>

<style>
body {
    margin: 0;
    font-family: Arial, sans-serif;
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100vh;
}

body.day { background: #ffffff; color: #000; }
body.night { background: #0b1a3a; color: #fff; }

#wrapper {
    display: flex;
    gap: 30px;
}

#boardContainer {
    width: 400px;
}

#debugContainer {
    width: 350px;
}

.row {
    display: flex;
    align-items: center;
    margin: 10px 0;
    padding: 15px;
    font-size: 32px;
    border-radius: 10px;
    font-weight: bold;
}

.blue { background: #0044ff; }
.green { background: #00aa44; }
.red { background: #cc0000; }
.orange { background: #ff8800; }
.purple { background: #9900cc; }

.icon {
    width: 60px;
    height: 60px;
    margin-right: 20px;
}

#debug {
    display: none;
    background: rgba(0,0,0,0.7);
    padding: 10px;
    border-radius: 8px;
    font-size: 14px;
}

button {
    margin-bottom: 10px;
    cursor: pointer;
}
</style>
</head>

<body class="night">

<div id="wrapper">

    <div id="boardContainer">
        <div id="board"></div>
    </div>

    <div id="debugContainer">
        <button id="toggleBtn">Показать debug</button>
        <div id="debug">
            <div><b>Статус:</b> <span id="statusText"></span></div>
            <pre id="json"></pre>
        </div>
    </div>

</div>

<script>
const ws = new WebSocket("ws://" + location.host + "/ws");

const colors = ["blue", "green", "red", "orange", "purple"];

const statusMap = {
    0: "Ошибок нет",
    1: "Пустая строка не найдена",
    2: "Ошибка HTTP",
    3: "Не HTTP",
    4: "Ошибка JSON / данных",
    5: "Нет type",
    6: "Нет version",
    7: "Нет datetime",
    8: "Нет pattern",
    10: "Неверный шаблон"
};

function setTheme(isDay) {
    document.body.classList.remove("day", "night");
    document.body.classList.add(isDay ? "day" : "night");
}

ws.onmessage = (event) => {
    const payload = JSON.parse(event.data);

    render(payload.data || {});
    updateDebug(payload);
};

function render(data) {
    const board = document.getElementById("board");

    board.innerHTML = "";

    setTheme(data.is_day === true);

    for (let i = 1; i <= 5; i++) {
        const key = "str" + i;

        if (!data[key]) continue;

        const row = document.createElement("div");

        row.className = "row " + colors[i - 1];

        let img = "";

        if (data[key].img) {
            img = `<img class="icon" src="/static/${data[key].img}.png">`;
        }

        const text = data[key].text || "";

        row.innerHTML = `${img}<span>${text}</span>`;

        board.appendChild(row);
    }
}

function updateDebug(payload) {
    document.getElementById("json").textContent =
        JSON.stringify(payload.data, null, 2);

    const status = payload.status ?? "-";

    document.getElementById("statusText").textContent =
        status + " — " + (statusMap[status] || "Неизвестно");
}

document.getElementById("toggleBtn").onclick = () => {
    const dbg = document.getElementById("debug");

    dbg.style.display =
        (dbg.style.display === "none") ? "block" : "none";
};
</script>

</body>
</html>
EOF

# --- create placeholders ---
echo "[7/8] Creating placeholder icons..."

touch car.png
touch ecar.png
touch moto.png
touch 2car.png
touch arrow_up.png
touch arrow_down.png
touch arrow_left.png
touch arrow_right.png

# --- create service ---
echo "[8/8] Creating systemd service..."

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Parking Board Emulator
After=network.target

[Service]
User=root
WorkingDirectory=${APP_DIR}

ExecStart=${APP_DIR}/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port ${PORT}

Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

echo
echo "======================================="
echo " Installation completed"
echo "======================================="
echo
echo "Service status:"
systemctl --no-pager status ${SERVICE_NAME} || true

echo
echo "Open in browser:"
echo "http://SERVER_IP:${PORT}"
echo
echo "Upload PNG icons into:"
echo "${APP_DIR}"
echo
