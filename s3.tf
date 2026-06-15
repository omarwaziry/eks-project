resource "aws_s3_bucket" "sample" {
  bucket        = "devsecops-demo-bucket-unique-suffix" 
  force_destroy = true
}