# Setup provider
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu-central-1"
  region = "eu-central-1"
}
# Setup customer application
# Lookup most recent AMI
data "aws_ami" "us-latest-image" {
  provider = aws.us-east-1
  most_recent = true
  owners      = var.ami_filter_owners

  filter {
    name   = "name"
    values = var.ami_filter_name
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "eu-latest-image" {
  provider = aws.eu-central-1
  most_recent = true
  owners      = var.ami_filter_owners

  filter {
    name   = "name"
    values = var.ami_filter_name
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "eu-vpc" {
  provider = aws.eu-central-1
  cidr_block = "172.17.0.0/16"

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_internet_gateway" "eu-gw" {
  provider = aws.eu-central-1
  vpc_id = aws_vpc.eu-vpc.id
}

resource "aws_default_route_table" "eu-table" {
  provider = aws.eu-central-1
  default_route_table_id = aws_vpc.eu-vpc.default_route_table_id
}

resource "aws_route" "eu-public-internet-gateway" {
  provider = aws.eu-central-1
  route_table_id         = aws_default_route_table.eu-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.eu-gw.id
}

data "aws_availability_zones" "eu-available" {
  provider = aws.eu-central-1
  state = "available"
}

resource "aws_subnet" "eu-subnet" {
  provider = aws.eu-central-1
  count                   = 2
  vpc_id                  = aws_vpc.eu-vpc.id
  availability_zone       = data.aws_availability_zones.eu-available.names[count.index]
  cidr_block              = "172.17.${count.index + 1}.0/24"
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_default_security_group" "eu-vpc-default" {
  provider = aws.eu-central-1
  vpc_id = aws_vpc.eu-vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc" "us-vpc" {
  provider = aws.us-east-1
  cidr_block = "172.16.0.0/16"

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_internet_gateway" "us-gw" {
  provider = aws.us-east-1
  vpc_id = aws_vpc.us-vpc.id
}

resource "aws_default_route_table" "us-table" {
  provider = aws.us-east-1
  default_route_table_id = aws_vpc.us-vpc.default_route_table_id
}

resource "aws_route" "us-public-internet-gateway" {
  provider = aws.us-east-1
  route_table_id         = aws_default_route_table.us-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.us-gw.id
}

data "aws_availability_zones" "us-available" {
  provider = aws.us-east-1
  state = "available"
}

resource "aws_subnet" "us-subnet" {
  provider = aws.us-east-1
  count                   = 2
  vpc_id                  = aws_vpc.us-vpc.id
  availability_zone       = data.aws_availability_zones.us-available.names[count.index]
  cidr_block              = "172.16.${count.index + 1}.0/24"
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_default_security_group" "us-vpc-default" {
  provider = aws.us-east-1
  vpc_id = aws_vpc.us-vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "eu-web" {
  provider = aws.eu-central-1
  ami           = data.aws_ami.eu-latest-image.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.eu-subnet[0].id
  key_name      = var.ssh_key_name
  iam_instance_profile = aws_iam_instance_profile.instance-profile.id

  user_data = <<EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y python3-flask
sudo apt-get install -y python3-pandas
sudo apt-get install -y python3-pymysql
sudo apt-get install -y python3-boto3

sudo useradd flask
sudo mkdir -p /opt/flask
sudo chown -R flask:flask /opt/flask
sudo git clone https://github.com/chrismatteson/terraform-chip-vault
cp -r terraform-chip-vault/flaskapp/* /opt/flask/

mysqldbcreds=$(cat <<MYSQLDBCREDS
{
  "username": "${aws_db_instance.eu-database.username}",
  "password": "${aws_db_instance.eu-database.password}",
  "hostname": "${aws_db_instance.eu-database.address}"
}
MYSQLDBCREDS
)

echo -e "$mysqldbcreds" > /opt/flask/mysqldbcreds.json

systemd=$(cat <<SYSTEMD
[Unit]
Description=Flask App for CHIP Vault Certification
After=network.target

[Service]
User=flask
WorkingDirectory=/opt/flask
ExecStart=/usr/bin/python3 app.py
Restart=always

[Install]
WantedBy=multi-user.target
SYSTEMD
)

echo -e "$systemd" > /etc/systemd/system/flask.service

sudo systemctl daemon-reload
sudo systemctl enable flask.service
sudo systemctl restart flask.service
EOF

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_instance" "us-web" {
  provider = aws.us-east-1
  ami           = data.aws_ami.us-latest-image.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.us-subnet[0].id
  key_name      = var.ssh_key_name
  iam_instance_profile = aws_iam_instance_profile.instance-profile.id

  user_data = <<EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y python3-flask
sudo apt-get install -y python3-pandas
sudo apt-get install -y python3-pymysql
sudo apt-get install -y python3-boto3

sudo useradd flask
sudo mkdir -p /opt/flask
sudo chown -R flask:flask /opt/flask
sudo git clone https://github.com/chrismatteson/terraform-chip-vault
cp -r terraform-chip-vault/flaskapp/* /opt/flask/

mysqldbcreds=$(cat <<MYSQLDBCREDS
{
  "username": "${aws_db_instance.us-database.username}",
  "password": "${aws_db_instance.us-database.password}",
  "hostname": "${aws_db_instance.us-database.address}"
}
MYSQLDBCREDS
)

echo -e "$mysqldbcreds" > /opt/flask/mysqldbcreds.json

systemd=$(cat <<SYSTEMD
[Unit]
Description=Flask App for CHIP Vault Certification
After=network.target

[Service]
User=flask
WorkingDirectory=/opt/flask
ExecStart=/usr/bin/python3 app.py
Restart=always

[Install]
WantedBy=multi-user.target
SYSTEMD
)

echo -e "$systemd" > /etc/systemd/system/flask.service

sudo systemctl daemon-reload
sudo systemctl enable flask.service
sudo systemctl restart flask.service
EOF

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_iam_role" "instance-role" {
  provider = aws.us-east-1
  name_prefix        = "${var.project_tag}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance-role.json
}

data "aws_iam_policy_document" "instance-role" {
  provider = aws.us-east-1
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "instance-profile" {
  provider = aws.us-east-1
  name_prefix = "${var.project_tag}-instance_profile"
  role        = aws_iam_role.instance-role.name
}

resource "aws_iam_role_policy_attachment" "SystemsManager" {
  provider = aws.us-east-1
  role       = aws_iam_role.instance-role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_db_subnet_group" "eu-db-subnet" {
  provider = aws.eu-central-1
  subnet_ids = aws_subnet.eu-subnet.*.id

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_db_instance" "eu-database" {
  provider = aws.eu-central-1
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  name                   = "mydb"
  username               = "foo"
  password               = "foobarbaz"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.eu-db-subnet.id
  vpc_security_group_ids = [aws_vpc.eu-vpc.default_security_group_id]
}

resource "aws_db_subnet_group" "us-db-subnet" {
  provider = aws.us-east-1
  subnet_ids = aws_subnet.us-subnet.*.id

  tags = merge(
    var.tags,
    {
      "ProjectTag" = var.project_tag
    },
  )
}

resource "aws_db_instance" "us-database" {
  provider = aws.us-east-1
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  name                   = "mydb"
  username               = "foo"
  password               = "foobarbaz"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.us-db-subnet.id
  vpc_security_group_ids = [aws_vpc.us-vpc.default_security_group_id]
}
