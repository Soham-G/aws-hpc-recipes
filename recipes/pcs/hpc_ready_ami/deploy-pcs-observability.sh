#!/bin/bash

# Configuration - Edit these variables as needed
S3_BUCKET="soham-hpc-stockholm-assets"  # Change to your S3 bucket name
S3_PREFIX="hpc-recipes-temp"            # Change to your preferred S3 prefix
REGION="eu-north-1"                     # Change to your preferred AWS region
STACK_NAME="pcs-ami-builder"            # Name for the CloudFormation stack
DISTRO="ubuntu-22-04"                   # Options: amzn-2, rocky-9, rhel-9, ubuntu-22-04
ARCHITECTURE="x86"                      # Options: x86, arm64
SEMANTIC_VERSION=$(date +%Y.%m.%d)      # Version tag for the AMI

# Display configuration
echo "============================================"
echo "PCS Observability Deployment Configuration:"
echo "============================================"
echo "S3 Bucket:     $S3_BUCKET"
echo "S3 Prefix:     $S3_PREFIX"
echo "AWS Region:    $REGION"
echo "Stack Name:    $STACK_NAME"
echo "Distribution:  $DISTRO"
echo "Architecture:  $ARCHITECTURE"
echo "Version:       $SEMANTIC_VERSION"
echo "============================================"
echo ""

# Confirm with user
read -p "Do you want to proceed with these settings? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Deployment cancelled."
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Function to upload files to S3
upload_to_s3() {
    local file=$1
    local s3_key=$2
    
    echo "Uploading $file to s3://$S3_BUCKET/$s3_key..."
    aws s3 cp "$file" "s3://$S3_BUCKET/$s3_key"
    
    if [ $? -ne 0 ]; then
        echo "Failed to upload $file to S3"
        return 1
    fi
    
    echo "Successfully uploaded $file to S3"
    return 0
}

# Step 1: Upload all necessary files to S3
echo "Step 1: Uploading files to S3..."

# Upload all script files
echo "Uploading script files..."
for script in ./assets/scripts/*.sh; do
    filename=$(basename "$script")
    upload_to_s3 "$script" "$S3_PREFIX/scripts/$filename"
done

# Upload all component YAML files
echo "Uploading component YAML files..."
for component in ./assets/components/*.yaml; do
    filename=$(basename "$component")
    upload_to_s3 "$component" "$S3_PREFIX/components/$filename"
done

# Upload other YAML files
echo "Uploading other YAML files..."
upload_to_s3 "./assets/create-pcs-image.yaml" "$S3_PREFIX/create-pcs-image.yaml"
upload_to_s3 "./assets/infrastructure-configurations.yaml" "$S3_PREFIX/infrastructure-configurations.yaml"
upload_to_s3 "./assets/pcs-observability.yaml" "$S3_PREFIX/pcs-observability.yaml"

# Upload Grafana dashboards if they exist
if [ -d "./assets/grafana-dashboards" ]; then
    echo "Uploading Grafana dashboards..."
    for dashboard in ./assets/grafana-dashboards/*.json; do
        if [ -f "$dashboard" ]; then
            filename=$(basename "$dashboard")
            upload_to_s3 "$dashboard" "$S3_PREFIX/grafana-dashboards/$filename"
        fi
    done
fi

# Modify nested-imagebuilder-components.yaml to use our S3 bucket
echo "Modifying nested-imagebuilder-components.yaml..."
cp ./assets/nested-imagebuilder-components.yaml "$TEMP_DIR/nested-imagebuilder-components.yaml"

# Replace all TemplateURL references to point to our bucket
sed -i '' "s|TemplateURL: !Sub 'https://\${HpcRecipesS3Bucket}.s3.us-east-1.amazonaws.com/\${HpcRecipesBranch}/recipes/pcs/hpc_ready_ami/assets/components/|TemplateURL: !Sub 'https://$S3_BUCKET.s3.$REGION.amazonaws.com/$S3_PREFIX/components/|g" "$TEMP_DIR/nested-imagebuilder-components.yaml"

# Fix the PrometheusAgentInstallerStack TemplateURL
sed -i '' "s|TemplateURL: !Sub 'https://\${HpcRecipesS3Bucket}.s3.\${AWS::Region}.amazonaws.com/\${HpcRecipesBranch}/components/install-prometheus-agent.yaml'|TemplateURL: !Sub 'https://$S3_BUCKET.s3.$REGION.amazonaws.com/$S3_PREFIX/components/install-prometheus-agent.yaml'|g" "$TEMP_DIR/nested-imagebuilder-components.yaml"

# Upload the modified nested-imagebuilder-components.yaml
upload_to_s3 "$TEMP_DIR/nested-imagebuilder-components.yaml" "$S3_PREFIX/nested-imagebuilder-components.yaml"

# Clean up
echo "Cleaning up temporary directory..."
rm -rf "$TEMP_DIR"

echo "All files uploaded successfully!"
echo ""

# Step 2: Deploy the CloudFormation stack
echo "Step 2: Deploying CloudFormation stack $STACK_NAME..."
aws cloudformation create-stack \
  --region $REGION \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameters \
    ParameterKey=Distro,ParameterValue=$DISTRO \
    ParameterKey=Architecture,ParameterValue=$ARCHITECTURE \
    ParameterKey=SemanticVersion,ParameterValue=$SEMANTIC_VERSION \
    ParameterKey=HpcRecipesS3Bucket,ParameterValue=$S3_BUCKET \
    ParameterKey=HpcRecipesBranch,ParameterValue=$S3_PREFIX \
    ParameterKey=S3BucketName,ParameterValue=$S3_BUCKET \
    ParameterKey=S3BucketPrefix,ParameterValue=$S3_PREFIX \
  --template-url https://$S3_BUCKET.s3.$REGION.amazonaws.com/$S3_PREFIX/create-pcs-image.yaml

if [ $? -eq 0 ]; then
  echo "============================================"
  echo "Stack creation initiated successfully!"
  echo "============================================"
  echo "You can monitor the stack creation progress in the CloudFormation console:"
  echo "https://$REGION.console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
  echo ""
  echo "Once the stack is created, the AMI build process will begin automatically."
  echo "This process can take 30-60 minutes to complete."
  echo ""
  echo "After the AMI is built, you can use it to launch PCS clusters with"
  echo "built-in observability using Amazon Managed Prometheus."
else
  echo "Failed to create stack. Please check the AWS CloudFormation console for details."
fi
