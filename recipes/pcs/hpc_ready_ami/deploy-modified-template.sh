#!/bin/bash

# Configuration
STACK_NAME="pcs-ami-builder"
REGION="eu-north-1"  # Change to your preferred region
DISTRO="ubuntu-22-04"  # Options: amzn-2, rocky-9, rhel-9, ubuntu-22-04
ARCHITECTURE="x86"  # Options: x86, arm64
S3_BUCKET="soham-hpc-stockholm-assets"
S3_PREFIX="hpc-recipes-temp"
SEMANTIC_VERSION=$(date +%Y.%m.%d)

# Deploy the main CloudFormation stack
echo "Deploying CloudFormation stack $STACK_NAME..."
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
  echo "Stack creation initiated successfully!"
  echo "You can monitor the stack creation progress in the CloudFormation console."
  echo "Once the stack is created, the AMI build process will begin automatically."
  echo "This process can take 30-60 minutes to complete."
else
  echo "Failed to create stack."
fi
