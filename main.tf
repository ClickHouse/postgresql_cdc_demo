terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.91.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

##############################
# VPC and Networking Resources
##############################

resource "aws_vpc" "cdc_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "cdc-demo-vpc"
  })
}

# Public Subnet for both EC2 and RDS
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.cdc_vpc.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = var.availability_zone_a
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "cdc-demo-public-subnet"
  })
}

# Public Subnet for both EC2 and RDS (Need two subnets for RDS)
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.cdc_vpc.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = var.availability_zone_b
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "cdc-demo-private-subnet"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cdc_vpc.id

  tags = merge(var.tags, {
    Name = "cdc-demo-igw"
  })
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cdc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, {
    Name = "cdc-demo-public-rt"
  })
}

# Associate Public Subnet with the Public Route Table
resource "aws_route_table_association" "public_rt_assoc_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

##############################
# Security Groups
##############################

# Security Group for the EC2 instance (data generator)
resource "aws_security_group" "ec2_sg" {
  name        = "cdc-demo-ec2-sg"
  description = "Allow SSH access to the data generator instance"
  vpc_id      = aws_vpc.cdc_vpc.id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For demo; restrict in production!
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "cdc-demo-ec2-sg"
  })
}

# Security Group for the RDS PostgreSQL instance
resource "aws_security_group" "rds_sg" {
  name        = "cdc-demo-rds-sg"
  description = "Allow PostgreSQL access from the EC2 instance and external CDC tools"
  vpc_id      = aws_vpc.cdc_vpc.id

  ingress {
    description     = "PostgreSQL access from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  ingress {
    description = "Public PostgreSQL access (for CDC tool)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For demo only; restrict this in production!
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "cdc-demo-rds-sg"
  })
}

##############################
# RDS PostgreSQL Instance (Publicly Accessible)
##############################

# DB Subnet Group using the Public Subnet so RDS gets a public IP
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "cdc-demo-rds-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  tags = merge(var.tags, {
    Name = "cdc-demo-rds-subnet-group"
  })
}

# Parameter group for PostgreSQL to enable logical replication
resource "aws_db_parameter_group" "postgres_params" {
  name        = "cdc-demo-postgres-params"
  family      = "postgres17"  # Make sure this matches your PostgreSQL version
  description = "Parameter group for CDC demo with logical replication enabled"

  parameter {
    name  = "rds.logical_replication"
    value = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "wal_sender_timeout"
    value = "0"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, {
    Name = "cdc-demo-postgres-params"
  })
}

resource "aws_db_instance" "postgres" {
  identifier             = "cdc-demo-postgres"
  engine                 = "postgres"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_type           = "gp2"
  username               = var.db_username
  password               = var.db_password
  db_name                = var.db_name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  parameter_group_name   = aws_db_parameter_group.postgres_params.name
  publicly_accessible    = true
  skip_final_snapshot    = true
  apply_immediately      = true

  tags = merge(var.tags, {
    Name = "cdc-demo-postgres"
  })
  
  depends_on = [aws_db_parameter_group.postgres_params]
}

# Null resource to handle the reboot after RDS instance creation
resource "null_resource" "rds_reboot" {
  triggers = {
    instance_id = aws_db_instance.postgres.id
  }

  provisioner "local-exec" {
    command = "aws rds reboot-db-instance --db-instance-identifier ${aws_db_instance.postgres.identifier} --profile ${var.aws_profile} --region ${var.aws_region}"
  }

  depends_on = [aws_db_instance.postgres]
}

##############################
# Data Generator EC2 Instance
##############################

# Fetch the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "data_generator" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    # Update system and install dependencies
    yum update -y
    yum install -y postgresql python3 python3-pip

    # Install Python dependencies with error handling
    pip3 install psycopg2-binary || {
      echo "Failed to install psycopg2-binary. Installing development dependencies."
      yum install -y postgresql-devel python3-devel gcc
      pip3 install psycopg2-binary
    }

    # Create the Python script directly (with very careful indentation)
    cat > /home/ec2-user/data_generator.py << 'ENDPYTHON'
#!/usr/bin/env python3
import time
import psycopg2
import random
import logging
import datetime
import sys
from contextlib import contextmanager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/home/ec2-user/data_generator.log"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Database connection parameters
DB_PARAMS = {
    "host": "${aws_db_instance.postgres.address}",
    "dbname": "${var.db_name}",
    "user": "${var.db_username}",
    "password": "${var.db_password}"
}

@contextmanager
def get_db_connection():
    """Context manager for database connections with error handling"""
    conn = None
    try:
        conn = psycopg2.connect(**DB_PARAMS)
        yield conn
    except psycopg2.Error as e:
        logger.error(f"Database connection error: {e}")
        if conn:
            conn.rollback()
        raise
    finally:
        if conn:
            conn.close()

def setup_database():
    """Create the schema and table if they don't exist"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                logger.info("Setting up database schema and tables...")
                cur.execute("CREATE SCHEMA IF NOT EXISTS source;")
                cur.execute("CREATE TABLE IF NOT EXISTS source.live_data (id SERIAL PRIMARY KEY, value INTEGER, created_at TIMESTAMPTZ DEFAULT NOW());")
                conn.commit()
                logger.info("Database setup completed successfully")
    except Exception as e:
        logger.error(f"Failed to set up database: {e}")
        raise

def main():
    """Main data generation function"""
    logger.info("Data generator starting up...")
    
    # Set up the database
    setup_database()
    
    # Track statistics
    start_time = datetime.datetime.now()
    record_count = 0
    
    try:
        while True:
            try:
                with get_db_connection() as conn:
                    with conn.cursor() as cur:
                        value = random.randint(1, 100)
                        cur.execute("INSERT INTO source.live_data (value) VALUES (%s) RETURNING id;", (value,))
                        inserted_id = cur.fetchone()[0]
                        conn.commit()
                        
                        record_count += 1
                        runtime = datetime.datetime.now() - start_time
                        
                        # Log periodic statistics
                        if record_count % 10 == 0:
                            logger.info(f"Inserted {record_count} records over {runtime}. Latest ID: {inserted_id}, Value: {value}")
                        
                        time.sleep(${var.data_generation_interval})
            except psycopg2.Error as e:
                logger.error(f"Database error: {e}")
                logger.info("Trying again in 30 seconds...")
                time.sleep(30)
    except KeyboardInterrupt:
        logger.info(f"Data generator stopped. Total records inserted: {record_count}, Total runtime: {runtime}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        raise

if __name__ == "__main__":
    main()
ENDPYTHON

    # After the script is created, manually verify its syntax before running it
    python3 -m py_compile /home/ec2-user/data_generator.py || {
      echo "Python syntax error detected. Not starting the service."
      cat /home/ec2-user/data_generator.py
      exit 1
    }

    # Create configuration script for ClickPipes user and replication
    cat > /home/ec2-user/configure_replication.sql << 'SQLEOF'
-- Create a dedicated user for ClickPipes
CREATE USER clickpipes_user PASSWORD '${var.clickpipes_user_password}';

-- Grant schema permissions for the source schema
GRANT USAGE ON SCHEMA "source" TO clickpipes_user;
GRANT SELECT ON ALL TABLES IN SCHEMA "source" TO clickpipes_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA "source" GRANT SELECT ON TABLES TO clickpipes_user;

-- Grant replication privileges
GRANT rds_replication TO clickpipes_user;

-- Create a publication for replication
CREATE PUBLICATION clickpipes_publication FOR ALL TABLES;
SQLEOF

    # Script to execute the SQL configuration
    cat > /home/ec2-user/setup_replication.sh << 'SETUPEOF'
#!/bin/bash
echo "Waiting for database to be ready..."
# Wait for the database to be fully ready after reboot
sleep 30

echo "Setting up ClickPipes replication configuration..."
PGPASSWORD="${var.db_password}" psql \
  -h ${aws_db_instance.postgres.address} \
  -U ${var.db_username} \
  -d ${var.db_name} \
  -f /home/ec2-user/configure_replication.sql

if [ $? -eq 0 ]; then
  echo "Replication configuration completed successfully."
else
  echo "Replication configuration failed. Check logs for details."
fi
SETUPEOF

    chmod +x /home/ec2-user/setup_replication.sh
    chown ec2-user:ec2-user /home/ec2-user/configure_replication.sql
    chown ec2-user:ec2-user /home/ec2-user/setup_replication.sh

    # Fix permissions
    chmod 755 /home/ec2-user/data_generator.py
    chown ec2-user:ec2-user /home/ec2-user/data_generator.py
    touch /home/ec2-user/data_generator.log
    chown ec2-user:ec2-user /home/ec2-user/data_generator.log

    # Create systemd service for auto-restart and persistence
    cat > /etc/systemd/system/data-generator.service << 'SERVICEEOF'
[Unit]
Description=Database Data Generator Service
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/data_generator.py
Restart=always
RestartSec=10
StandardOutput=append:/home/ec2-user/data_generator.log
StandardError=append:/home/ec2-user/data_generator.log

[Install]
WantedBy=multi-user.target
SERVICEEOF

    # Enable and start the service
    systemctl daemon-reload
    systemctl enable data-generator.service
    
    # Run the replication setup script
    /home/ec2-user/setup_replication.sh > /home/ec2-user/replication_setup.log 2>&1
    
    # Start data generator service after replication is configured
    systemctl start data-generator.service

    # Add a status script to easily check the data generator
    cat > /home/ec2-user/check_generator.sh << 'SCRIPTEOF'
#!/bin/bash
echo "=== Data Generator Service Status ==="
systemctl status data-generator.service
echo ""
echo "=== Last 20 log entries ==="
tail -n 20 /home/ec2-user/data_generator.log
echo ""
echo "=== Database Record Count ==="
sudo -u ec2-user psql -h ${aws_db_instance.postgres.address} -d ${var.db_name} -U ${var.db_username} -c "SELECT COUNT(*) FROM source.live_data;"
SCRIPTEOF

    chmod +x /home/ec2-user/check_generator.sh
    chown ec2-user:ec2-user /home/ec2-user/check_generator.sh

    # Create a PGPASSFILE to avoid password prompts
    echo "${aws_db_instance.postgres.address}:5432:${var.db_name}:${var.db_username}:${var.db_password}" > /home/ec2-user/.pgpass
    chmod 600 /home/ec2-user/.pgpass
    chown ec2-user:ec2-user /home/ec2-user/.pgpass
  EOF

  tags = merge(var.tags, {
    Name = "cdc-demo-data-generator"
  })
}

