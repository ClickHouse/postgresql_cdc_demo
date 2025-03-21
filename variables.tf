variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
  default     = "sa"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_a_cidr" {
  description = "CIDR block for public subnet A"
  type        = string
  default     = "10.0.3.0/24"
}

variable "public_subnet_b_cidr" {
  description = "CIDR block for public subnet B"
  type        = string
  default     = "10.0.4.0/24"
}

variable "availability_zone_a" {
  description = "Availability zone A"
  type        = string
  default     = "ap-southeast-1a"
}

variable "availability_zone_b" {
  description = "Availability zone B"
  type        = string
  default     = "ap-southeast-1b"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "17.2"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance"
  type        = number
  default     = 20
}

variable "db_username" {
  description = "Master username for RDS instance"
  type        = string
  default     = "clickers"
}

variable "db_password" {
  description = "Master password for RDS instance"
  type        = string
  default     = "!YouShallNotPassWithThisPassword!" # Demo only – use secure credentials in production
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "ch_cdc_demo"
}

variable "clickpipes_username" {
  description = "Username for ClickPipes user"
  type        = string
  default     = "clickpipes_user"
}

variable "clickpipes_user_password" {
  description = "Password for ClickPipes user"
  type        = string
  default     = "ClickPipes@2025"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for data generator"
  type        = string
  default     = "t3.micro"
}

variable "data_generation_interval" {
  description = "Interval between data generation in seconds"
  type        = number
  default     = 5
}

variable "tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "cdc"
    Owner       = "SA-Team"                  # Team or owner name
    ManagedBy   = "terraform"                  # Infrastructure management tool
  }
}

variable "rds_subnet_group_name" {
  description = "Name of the RDS subnet group"
  type        = string
  default     = "cdc-demo-rds-subnet-group"
}

variable "rds_parameter_group_name" {
  description = "Name of the RDS parameter group"
  type        = string
  default     = "cdc-demo-postgres-params"
}

variable "rds_instance_identifier" {
  description = "Identifier for the RDS instance"
  type        = string
  default     = "cdc-demo-postgres"
} 