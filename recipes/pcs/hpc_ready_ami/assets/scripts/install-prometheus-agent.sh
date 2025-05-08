#!/bin/bash

# Script to install and configure Prometheus agent for PCS clusters
# This script installs the Prometheus agent and configures it to send metrics to Amazon Managed Prometheus
# It also installs exporters for EFA and GPU metrics if hardware is present

set -e

# Source common functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"

# Default values
PROMETHEUS_ENDPOINT=""
SCRAPE_INTERVAL="15s"
RETENTION_TIME="1h"
CONFIG_DIR="/etc/prometheus"
DATA_DIR="/var/lib/prometheus"
INSTALL_GPU_EXPORTER="auto"
INSTALL_EFA_EXPORTER="auto"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --endpoint)
      PROMETHEUS_ENDPOINT="$2"
      shift
      shift
      ;;
    --scrape-interval)
      SCRAPE_INTERVAL="$2"
      shift
      shift
      ;;
    --retention)
      RETENTION_TIME="$2"
      shift
      shift
      ;;
    --gpu-exporter)
      INSTALL_GPU_EXPORTER="$2"
      shift
      shift
      ;;
    --efa-exporter)
      INSTALL_EFA_EXPORTER="$2"
      shift
      shift
      ;;
    *)
      echo "Unknown option: $key"
      exit 1
      ;;
  esac
done

# Detect OS and set package manager
detect_os
detect_arch

echo "Installing Prometheus agent on ${OS_DISTRO} ${OS_VERSION} (${ARCH})"

# Check for GPU presence
check_gpu_presence() {
  if [ "$INSTALL_GPU_EXPORTER" = "auto" ]; then
    if command -v nvidia-smi &> /dev/null; then
      echo "NVIDIA GPU detected, will install GPU exporter"
      INSTALL_GPU_EXPORTER="true"
    else
      echo "No NVIDIA GPU detected, skipping GPU exporter"
      INSTALL_GPU_EXPORTER="false"
    fi
  fi
}

# Check for EFA presence
check_efa_presence() {
  if [ "$INSTALL_EFA_EXPORTER" = "auto" ]; then
    if [ -d "/opt/amazon/efa" ] || [ -d "/opt/amazon/openmpi" ]; then
      echo "EFA detected, will install EFA exporter"
      INSTALL_EFA_EXPORTER="true"
    else
      echo "No EFA detected, skipping EFA exporter"
      INSTALL_EFA_EXPORTER="false"
    fi
  fi
}

# Create prometheus user and directories
create_prometheus_user() {
  echo "Creating prometheus user and directories"
  
  # Create user if it doesn't exist
  if ! id -u prometheus &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false prometheus
  fi
  
  # Create directories
  mkdir -p ${CONFIG_DIR} ${DATA_DIR}
  chown -R prometheus:prometheus ${CONFIG_DIR} ${DATA_DIR}
}

# Download and install Prometheus
install_prometheus() {
  local PROMETHEUS_VERSION="2.45.0"
  local DOWNLOAD_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
  
  echo "Downloading Prometheus ${PROMETHEUS_VERSION}"
  
  # Download and extract Prometheus
  cd /tmp
  curl -L -O ${DOWNLOAD_URL}
  tar xvf prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz
  
  # Copy binaries
  cp prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}/prometheus /usr/local/bin/
  cp prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}/promtool /usr/local/bin/
  
  # Set permissions
  chown prometheus:prometheus /usr/local/bin/prometheus
  chown prometheus:prometheus /usr/local/bin/promtool
  
  # Copy config files
  cp -r prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}/consoles ${CONFIG_DIR}
  cp -r prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}/console_libraries ${CONFIG_DIR}
  
  # Set permissions
  chown -R prometheus:prometheus ${CONFIG_DIR}/consoles
  chown -R prometheus:prometheus ${CONFIG_DIR}/console_libraries
  
  # Clean up
  rm -rf prometheus-${PROMETHEUS_VERSION}.linux-${ARCH} prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz
}

# Configure Prometheus
configure_prometheus() {
  echo "Configuring Prometheus"
  
  # Create prometheus.yml
  cat > ${CONFIG_DIR}/prometheus.yml << EOF
global:
  scrape_interval: ${SCRAPE_INTERVAL}
  evaluation_interval: ${SCRAPE_INTERVAL}
  
remote_write:
  - url: ${PROMETHEUS_ENDPOINT}api/v1/remote_write
    sigv4:
      region: ${AWS_REGION}

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  
  - job_name: 'slurm'
    static_configs:
      - targets: ['localhost:9101']
EOF

  # Add GPU exporter config if enabled
  if [ "$INSTALL_GPU_EXPORTER" = "true" ]; then
    cat >> ${CONFIG_DIR}/prometheus.yml << EOF
  
  - job_name: 'nvidia_gpu'
    static_configs:
      - targets: ['localhost:9835']
EOF
  fi

  # Add EFA exporter config if enabled
  if [ "$INSTALL_EFA_EXPORTER" = "true" ]; then
    cat >> ${CONFIG_DIR}/prometheus.yml << EOF
  
  - job_name: 'efa_metrics'
    static_configs:
      - targets: ['localhost:9400']
EOF
  fi
  
  chown prometheus:prometheus ${CONFIG_DIR}/prometheus.yml
}

# Create systemd service
create_systemd_service() {
  echo "Creating systemd service"
  
  cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=${CONFIG_DIR}/prometheus.yml \
  --storage.tsdb.path=${DATA_DIR} \
  --storage.tsdb.retention.time=${RETENTION_TIME} \
  --web.console.templates=${CONFIG_DIR}/consoles \
  --web.console.libraries=${CONFIG_DIR}/console_libraries \
  --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable prometheus
  systemctl start prometheus
}

# Install Node Exporter
install_node_exporter() {
  echo "Installing Node Exporter"
  
  local NODE_EXPORTER_VERSION="1.6.1"
  local DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
  
  # Create user if it doesn't exist
  if ! id -u node_exporter &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false node_exporter
  fi
  
  # Download and extract Node Exporter
  cd /tmp
  curl -L -O ${DOWNLOAD_URL}
  tar xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz
  
  # Copy binary
  cp node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}/node_exporter /usr/local/bin/
  chown node_exporter:node_exporter /usr/local/bin/node_exporter
  
  # Create systemd service
  cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
  
  # Clean up
  rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH} node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz
  
  systemctl daemon-reload
  systemctl enable node_exporter
  systemctl start node_exporter
}

# Install Slurm Exporter
install_slurm_exporter() {
  echo "Installing Slurm Exporter"
  
  local SLURM_EXPORTER_VERSION="0.20"
  local DOWNLOAD_URL="https://github.com/vpenso/prometheus-slurm-exporter/releases/download/${SLURM_EXPORTER_VERSION}/prometheus-slurm-exporter"
  
  # Create user if it doesn't exist
  if ! id -u slurm_exporter &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false slurm_exporter
  fi
  
  # Download Slurm Exporter
  cd /tmp
  curl -L -o prometheus-slurm-exporter ${DOWNLOAD_URL}
  
  # Copy binary
  cp prometheus-slurm-exporter /usr/local/bin/
  chmod +x /usr/local/bin/prometheus-slurm-exporter
  chown slurm_exporter:slurm_exporter /usr/local/bin/prometheus-slurm-exporter
  
  # Create systemd service
  cat > /etc/systemd/system/slurm_exporter.service << EOF
[Unit]
Description=Slurm Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=slurm_exporter
Group=slurm_exporter
Type=simple
ExecStart=/usr/local/bin/prometheus-slurm-exporter -listen-address=:9101

[Install]
WantedBy=multi-user.target
EOF
  
  # Clean up
  rm -f /tmp/prometheus-slurm-exporter
  
  systemctl daemon-reload
  systemctl enable slurm_exporter
  systemctl start slurm_exporter
}

# Main execution
if [ -z "$PROMETHEUS_ENDPOINT" ]; then
  echo "Error: Prometheus endpoint is required. Use --endpoint parameter."
  exit 1
fi

# Get AWS region from instance metadata if not set
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
fi

# Check for hardware
check_gpu_presence
check_efa_presence

create_prometheus_user
install_prometheus
configure_prometheus
create_systemd_service
install_node_exporter
install_slurm_exporter

# Install GPU and EFA exporters if hardware is present
if [ "$INSTALL_GPU_EXPORTER" = "true" ]; then
  install_nvidia_exporter
fi

if [ "$INSTALL_EFA_EXPORTER" = "true" ]; then
  install_efa_exporter
fi

echo "Prometheus agent installation completed successfully"
exit 0
# Install NVIDIA GPU Exporter
install_nvidia_exporter() {
  if [ "$INSTALL_GPU_EXPORTER" != "true" ]; then
    return 0
  fi

  echo "Installing NVIDIA GPU Exporter"
  
  # Create user if it doesn't exist
  if ! id -u nvidia_exporter &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false nvidia_exporter
  fi
  
  # Install NVIDIA DCGM if not already installed
  if ! command -v dcgmi &> /dev/null; then
    echo "Installing NVIDIA DCGM"
    
    case ${OS_DISTRO} in
      ubuntu)
        # Add NVIDIA repository
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID | sed -e 's/\.//g')
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update
        apt-get install -y datacenter-gpu-manager
        ;;
      amzn|rhel|rocky)
        # For RHEL-based systems
        dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel8/x86_64/cuda-rhel8.repo
        dnf install -y datacenter-gpu-manager
        ;;
    esac
    
    # Start DCGM service
    systemctl --now enable nvidia-dcgm
  fi
  
  # Download and install DCGM exporter
  local DCGM_EXPORTER_VERSION="2.4.0"
  local DOWNLOAD_URL="https://github.com/NVIDIA/dcgm-exporter/releases/download/v${DCGM_EXPORTER_VERSION}/dcgm-exporter"
  
  curl -L -o /usr/local/bin/dcgm-exporter ${DOWNLOAD_URL}
  chmod +x /usr/local/bin/dcgm-exporter
  chown nvidia_exporter:nvidia_exporter /usr/local/bin/dcgm-exporter
  
  # Create systemd service
  cat > /etc/systemd/system/nvidia_exporter.service << EOF
[Unit]
Description=NVIDIA GPU Metrics Exporter
Wants=nvidia-dcgm.service
After=nvidia-dcgm.service

[Service]
User=nvidia_exporter
Group=nvidia_exporter
Type=simple
ExecStart=/usr/local/bin/dcgm-exporter --port=9835

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable nvidia_exporter
  systemctl start nvidia_exporter
}

# Install EFA Metrics Exporter
install_efa_exporter() {
  if [ "$INSTALL_EFA_EXPORTER" != "true" ]; then
    return 0
  fi

  echo "Installing EFA Metrics Exporter"
  
  # Create user if it doesn't exist
  if ! id -u efa_exporter &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false efa_exporter
  fi
  
  # Install dependencies
  case ${OS_DISTRO} in
    ubuntu)
      apt-get update
      apt-get install -y python3 python3-pip
      ;;
    amzn|rhel|rocky)
      dnf install -y python3 python3-pip
      ;;
  esac
  
  # Create EFA exporter script
  mkdir -p /opt/efa-exporter
  
  cat > /opt/efa-exporter/efa_exporter.py << 'EOF'
#!/usr/bin/env python3
import os
import re
import time
import socket
from http.server import HTTPServer, BaseHTTPRequestHandler

# EFA metrics to collect
EFA_METRICS = {
    'tx_bytes': 'efa_transmit_bytes_total',
    'rx_bytes': 'efa_receive_bytes_total',
    'tx_pkts': 'efa_transmit_packets_total',
    'rx_pkts': 'efa_receive_packets_total',
    'rx_drops': 'efa_receive_drops_total',
    'tx_drops': 'efa_transmit_drops_total',
    'rdma_read_bytes': 'efa_rdma_read_bytes_total',
    'rdma_write_bytes': 'efa_rdma_write_bytes_total',
    'rdma_read_wr': 'efa_rdma_read_work_requests_total',
    'rdma_write_wr': 'efa_rdma_write_work_requests_total'
}

def get_efa_interfaces():
    """Get list of EFA interfaces"""
    interfaces = []
    try:
        with open('/proc/net/dev', 'r') as f:
            for line in f:
                if 'efa' in line:
                    interface = line.split(':')[0].strip()
                    interfaces.append(interface)
    except Exception as e:
        print(f"Error getting EFA interfaces: {e}")
    return interfaces

def get_efa_stats(interface):
    """Get EFA statistics for a specific interface"""
    stats = {}
    try:
        with open(f'/proc/net/dev', 'r') as f:
            for line in f:
                if interface in line:
                    parts = line.split(':')
                    if len(parts) < 2:
                        continue
                    values = parts[1].strip().split()
                    stats['rx_bytes'] = values[0]
                    stats['rx_pkts'] = values[1]
                    stats['rx_drops'] = values[3]
                    stats['tx_bytes'] = values[8]
                    stats['tx_pkts'] = values[9]
                    stats['tx_drops'] = values[11]
                    break
    except Exception as e:
        print(f"Error getting stats for {interface}: {e}")
    
    # Try to get RDMA stats if available
    try:
        rdma_stats_path = f'/sys/class/infiniband/{interface}/ports/1/counters'
        if os.path.exists(rdma_stats_path):
            for metric in ['rdma_read_bytes', 'rdma_write_bytes', 'rdma_read_wr', 'rdma_write_wr']:
                try:
                    with open(f'{rdma_stats_path}/{metric}', 'r') as f:
                        stats[metric] = f.read().strip()
                except:
                    pass
    except Exception as e:
        print(f"Error getting RDMA stats for {interface}: {e}")
    
    return stats

class EFAMetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            
            # Get hostname
            hostname = socket.gethostname()
            
            # Get EFA interfaces
            interfaces = get_efa_interfaces()
            
            # Collect metrics
            output = []
            output.append('# HELP efa_up EFA interface is up (1) or down (0)')
            output.append('# TYPE efa_up gauge')
            
            for interface in interfaces:
                output.append(f'efa_up{{instance="{hostname}",interface="{interface}"}} 1')
                
                stats = get_efa_stats(interface)
                for stat_key, metric_name in EFA_METRICS.items():
                    if stat_key in stats:
                        output.append(f'# HELP {metric_name} EFA {stat_key.replace("_", " ")}')
                        output.append(f'# TYPE {metric_name} counter')
                        output.append(f'{metric_name}{{instance="{hostname}",interface="{interface}"}} {stats[stat_key]}')
            
            self.wfile.write('\n'.join(output).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run_server(port=9400):
    server_address = ('', port)
    httpd = HTTPServer(server_address, EFAMetricsHandler)
    print(f'Starting EFA exporter on port {port}')
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()
EOF
  
  chmod +x /opt/efa-exporter/efa_exporter.py
  chown -R efa_exporter:efa_exporter /opt/efa-exporter
  
  # Create systemd service
  cat > /etc/systemd/system/efa_exporter.service << EOF
[Unit]
Description=EFA Metrics Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=efa_exporter
Group=efa_exporter
Type=simple
ExecStart=/usr/bin/python3 /opt/efa-exporter/efa_exporter.py

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable efa_exporter
  systemctl start efa_exporter
}
