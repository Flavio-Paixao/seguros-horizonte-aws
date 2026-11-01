#!/bin/bash
set -euxo pipefail

# 1. Atualiza o sistema e instala o necessário (Amazon Linux 2023 usa dnf)
dnf update -y
dnf install -y python3 amazon-cloudwatch-agent

# 2. Cria o servidor de saúde (responde 200 em /health)
mkdir -p /opt/app
cat > /opt/app/app.py << 'PYEOF'
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass


HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
PYEOF

# 3. Registra como serviço (sobe no boot e reinicia se cair)
cat > /etc/systemd/system/app.service << 'UNITEOF'
[Unit]
Description=${project_name} - app (endpoint de saude)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now app.service

echo "Instancia iniciada em $(date)" >> /var/log/user-data.log
