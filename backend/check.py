import boto3

# sts = dịch vụ danh tính; gọi thử để chắc credentials hoạt động trong code
sts = boto3.client("sts", region_name="us-east-1")
print(sts.get_caller_identity()["Arn"])
