# PCS Observability with Amazon Managed Prometheus

This document describes the observability infrastructure created for AWS Parallel Computing Service (PCS) using Amazon Managed Prometheus.

## Overview

The CloudFormation template `pcs-observability.yaml` creates the following resources:

1. **Amazon Managed Prometheus Workspace** - A fully managed Prometheus-compatible monitoring service
2. **IAM Roles and Policies** - For secure access to the monitoring services
3. **CloudWatch Dashboard** - For basic PCS metrics visualization
4. **SSM Parameters** - To store endpoints for easy reference

Additionally, the following components are provided:

1. **Prometheus Agent Installation Script** - For installing and configuring Prometheus on PCS nodes
2. **EC2 ImageBuilder Component** - For integrating Prometheus agent into PCS AMIs

## Deployment Instructions

### 1. Deploy the Observability Infrastructure

deploy template: /assets/pcs-observability.yaml

### 2. Build PCS AMI with Prometheus Agent

add your s3 bucket and upload the modified files there so we can use it in the imagebuilder:

modify this script with your bucket and run:

```bash
./upload-all-to-s3.sh
```

Then deploy the CloudFormation stack to build the AMI:

```bash
./deploy-modified-template.sh
```

This script will:
- Create a CloudFormation stack that builds a PCS-ready AMI
- Include the Prometheus agent component in the AMI
- Use the forked version of the components from GitHub

You can modify the variables at the top of the `deploy-modified-template.sh` script to customize:
- Stack name
- AWS region
- Linux distribution (Amazon Linux 2, RHEL 9, Rocky Linux 9, or Ubuntu 22.04)
- Architecture (x86 or arm64)
- S3 bucket and prefix

### 3. Visualizing Metrics

You can visualize the metrics collected by Prometheus using:

1. The deployed Grafana installation
2. Amazon CloudWatch dashboards created by the template
3. Any Prometheus-compatible visualization tool

To configure your visualization tool:
1. Use the Amazon Managed Prometheus workspace endpoint from SSM Parameter Store
2. Import the pre-configured dashboard from `assets/dashboards/pcs-cluster-dashboard.json` if using Grafana

## Using the Modified Template

The modified template in this repository includes several enhancements:

1. **Integrated Prometheus Agent** - The AMI build process automatically includes the Prometheus agent
2. **Auto-Configuration** - The agent is pre-configured to send metrics to your Amazon Managed Prometheus workspace
3. **Custom Dashboard** - A PCS-specific Grafana dashboard is included for immediate visibility

### Steps to Use the Modified Template

1. Clone the repository and navigate to the hpc_ready_ami directory:
   ```bash
   git clone https://github.com/Soham-G/aws-hpc-recipes.git -b pcs-observability
   cd aws-hpc-recipes/recipes/pcs/hpc_ready_ami
   ```

2. Upload the required files to your S3 bucket:
   ```bash
   ./upload-to-s3.sh
   ```

3. Deploy the CloudFormation stack:
   ```bash
   ./deploy-modified-template.sh
   ```

4. Monitor the stack creation in the CloudFormation console

5. Once the AMI is built, you can use it to launch PCS clusters with built-in observability

### Customizing the Deployment

You can customize the deployment by editing the following files:

- `upload-to-s3.sh` - Modify S3 bucket, prefix, and which files to upload
- `deploy-modified-template.sh` - Change region, distribution, architecture, etc.
- `assets/components/install-prometheus-agent.yaml` - Customize the Prometheus agent configuration

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
2. Adding additional dashboards to your preferred visualization tool
3. Setting up alerts in Amazon Managed Prometheus
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
- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
