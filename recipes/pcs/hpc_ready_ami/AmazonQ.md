# PCS Observability with Amazon Managed Prometheus and Grafana

This document describes the observability infrastructure created for AWS Parallel Computing Service (PCS) using Amazon Managed Prometheus and Amazon Managed Grafana.

## Overview

The CloudFormation template `pcs-observability.yaml` creates the following resources:

1. **Amazon Managed Prometheus Workspace** - A fully managed Prometheus-compatible monitoring service
2. **Amazon Managed Grafana Workspace** - A fully managed Grafana service for visualizing metrics
3. **IAM Roles and Policies** - For secure access to the monitoring services
4. **CloudWatch Dashboard** (optional) - For basic PCS metrics visualization
5. **SSM Parameters** - To store endpoints for easy reference

Additionally, the following components are provided:

1. **Prometheus Agent Installation Script** - For installing and configuring Prometheus on PCS nodes
2. **EC2 ImageBuilder Component** - For integrating Prometheus agent into PCS AMIs
3. **Grafana Dashboard Template** - Pre-configured dashboard for PCS metrics visualization

## Deployment Instructions

### 1. Deploy the Observability Infrastructure

```bash
aws cloudformation create-stack \
  --stack-name pcs-observability \
  --template-body file://assets/pcs-observability.yaml \
  --parameters \
    ParameterKey=GrafanaAdminUserEmail,ParameterValue=your-email@example.com \
  --capabilities CAPABILITY_NAMED_IAM
```

### 2. Add Prometheus Agent to PCS AMIs

Deploy the EC2 ImageBuilder component:

```bash
aws cloudformation create-stack \
  --stack-name prometheus-agent-component \
  --template-body file://assets/components/install-prometheus-agent.yaml
```

Add the component to your PCS AMI build pipeline.

### 3. Configure Grafana

1. Access the Grafana workspace using the URL from the CloudFormation outputs
2. Add Amazon Managed Prometheus as a data source
3. Import the pre-configured dashboard from `assets/grafana-dashboards/pcs-cluster-dashboard.json`

## Metrics Collected

The Prometheus agent collects the following metrics:

- **Node Metrics**:
  - CPU utilization
  - Memory usage
  - Disk I/O
  - Network traffic
  - System load

- **Slurm Metrics**:
  - Job status (pending, running, completed)
  - Queue statistics
  - Node allocation
  - Resource utilization
  
- **GPU Metrics** (when GPU is present):
  - GPU utilization
  - GPU memory usage
  - GPU temperature
  - GPU power consumption
  
- **EFA Metrics** (when EFA is present):
  - EFA network traffic (transmit/receive bytes)
  - EFA packet rate
  - EFA packet drops
  - RDMA read/write operations

## Customization

You can customize the monitoring setup by:

1. Modifying the Prometheus configuration in the installation script
2. Adding additional Grafana dashboards
3. Setting up alerts in Grafana
4. Integrating with other AWS services like CloudWatch or AWS Lambda

## Troubleshooting

If you encounter issues:

1. Check that the Prometheus agent is running on the nodes:
   ```bash
   systemctl status prometheus
   ```

2. Verify connectivity to Amazon Managed Prometheus:
   ```bash
   curl -v <prometheus-endpoint>/api/v1/status/config
   ```

3. Check IAM permissions for the EC2 instances

## References

- [Amazon Managed Prometheus Documentation](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)
- [Amazon Managed Grafana Documentation](https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Service-Grafana.html)
- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
