#!/bin/bash

# Configuration
S3_BUCKET="soham-hpc-stockholm-assets"
S3_PREFIX="hpc-recipes-temp"
REGION="eu-north-1"

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
echo "To deploy the CloudFormation stack, run:"
echo "./deploy-modified-template.sh"
