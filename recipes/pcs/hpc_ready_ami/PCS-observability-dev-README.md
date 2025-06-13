# PCS Observability with Amazon Managed Prometheus

This document describes how to set up observability for AWS Parallel Computing Service (PCS) using Amazon Managed Prometheus.

## Overview

The solution creates the following resources:

1. **Amazon Managed Prometheus Workspace** - A fully managed Prometheus-compatible monitoring service
2. **PCS-ready AMI with Prometheus Agent** - Custom AMI with pre-configured monitoring capabilities
3. **CloudWatch Dashboard** - For basic PCS metrics visualization
4. **IAM Roles and Policies** - For secure access to monitoring services

## Quick Start Deployment

### Deploy grafana instance and prometheus store

1. Deploy script: `assets/pcs-observability.yaml`. This creates the infrastructure required to store and display the observability metrics, which is the Prometheus workspace, the Grafana instance, and the associated roles.

### Create AMI with Prometheus agent

2. Clone the repository and navigate to the directory:
   ```bash
   git clone https://github.com/Soham-G/aws-hpc-recipes.git -b pcs-observability
   cd aws-hpc-recipes/recipes/pcs/hpc_ready_ami
   ```

3. Edit the configuration variables in `deploy-pcs-observability.sh`:
   ```bash
   # Open the file in your preferred editor
   vim deploy-pcs-observability.sh
   
   # Edit these variables at the top of the file:
   S3_BUCKET="your-s3-bucket-name"
   S3_PREFIX="your-prefix"
   REGION="your-aws-region"
   DISTRO="ubuntu-22-04"  # Options: amzn-2, rocky-9, rhel-9, ubuntu-22-04
   ARCHITECTURE="x86"     # Options: x86, arm64
   ```

4. Run the deployment script:
   ```bash
   ./deploy-pcs-observability.sh
   ```

5. Monitor the stack creation in the CloudFormation console

6. Once the AMI is built, you can use it to launch PCS clusters with built-in observability

## Visualizing Metrics

You can visualize the metrics using:

1. The deployed Grafana installation (if configured)
2. Amazon CloudWatch dashboards created by the template
3. Any Prometheus-compatible visualization tool

To configure your visualization tool:
1. Use the Amazon Managed Prometheus workspace endpoint from SSM Parameter Store
2. Import the pre-configured dashboard from `assets/grafana-dashboards/pcs-cluster-dashboard.json` if using Grafana

## Metrics Collected

The Prometheus agent collects:

- **Node Metrics**: CPU, memory, disk I/O, network traffic, system load
- **Slurm Metrics**: Job status, queue statistics, node allocation, resource utilization
- **GPU Metrics** (when present): Utilization, memory usage, temperature, power consumption
- **EFA Metrics** (when present): Network traffic, packet rate, packet drops, RDMA operations

## Troubleshooting

If you encounter issues:

1. Check that the Prometheus agent is running:
   ```bash
   systemctl status prometheus
   ```

2. Verify connectivity to Amazon Managed Prometheus:
   ```bash
   curl -v <prometheus-endpoint>/api/v1/status/config
   ```

3. Check IAM permissions for the EC2 instances

4. Review CloudFormation stack events for any deployment errors

## References

- [Amazon Managed Prometheus Documentation](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)
- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
