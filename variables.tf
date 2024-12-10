# AWS Region
variable "region" {
  default = "us-east-1"
}

# VPC CIDR Block
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

# Public Subnets CIDR Blocks
variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Private Subnets CIDR Blocks
variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

# Instance Type for EC2
variable "instance_type" {
  default = "t2.micro"
}

# Key Pair Name
variable "key_pair" {
  description = "Key pair to use for SSH access"
  default     = "app-php-tf"
}

# AMI ID for Launch Template
variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  default     = "ami-0866a3c8686eaeeba"
}

# Public Key Path
variable "public_key_path" {
  description = "Path to the public key file for the key pair"
  default     = "~/.ssh/id_rsa.pub"
}

# Database Username
variable "db_username" {
  description = "Username for the RDS MySQL database"
  default     = "admin"
}

# Database Password
variable "db_password" {
  description = "Password for the RDS MySQL database"
  default     = "password"
  sensitive   = true
}

# Database Name
variable "db_name" {
  description = "Name of the RDS MySQL database"
  default     = "MyAppDB"
}
