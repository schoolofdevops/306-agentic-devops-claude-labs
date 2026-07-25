output "bucket_arn" {
  description = "ARN of the assets S3 bucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_name" {
  description = "Name of the assets S3 bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_id" {
  description = "ID of the assets S3 bucket."
  value       = aws_s3_bucket.assets.id
}
