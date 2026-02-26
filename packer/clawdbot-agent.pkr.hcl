packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ami_name_prefix" {
  type    = string
  default = "clawdbot-agent"
}

source "amazon-ebs" "clawdbot" {
  ami_name      = "${var.ami_name_prefix}-{{timestamp}}"
  instance_type = var.instance_type
  region        = var.aws_region

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }

  ssh_username = "ubuntu"

  ami_description = "ClawdBot Agent AMI - Ubuntu 24.04 with Node.js, Playwright, and agent runtime"

  tags = {
    Name        = "${var.ami_name_prefix}"
    Environment = "production"
    ManagedBy   = "packer"
    CreatedAt   = "{{timestamp}}"
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "clawdbot-agent"
  sources = ["source.amazon-ebs.clawdbot"]

  # Update system
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get install -y curl git jq postgresql-client python3-pip unzip"
    ]
  }

  # Install Node.js 22
  provisioner "shell" {
    inline = [
      "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -",
      "sudo apt-get install -y nodejs",
      "node --version",
      "npm --version"
    ]
  }

  # Install ClawdBot
  provisioner "shell" {
    inline = [
      "sudo npm install -g clawdbot",
      "clawdbot --version || echo 'ClawdBot installed'"
    ]
  }

  # Install Playwright with dependencies
  provisioner "shell" {
    inline = [
      "sudo npx playwright install-deps chromium",
      "npx playwright install chromium"
    ]
  }

  # Create agent directories
  provisioner "shell" {
    inline = [
      "mkdir -p /home/ubuntu/.clawdbot/identity",
      "mkdir -p /home/ubuntu/agent",
      "mkdir -p /opt/clawdbot"
    ]
  }

  # Upload bootstrap script
  provisioner "file" {
    source      = "scripts/bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/bootstrap.sh /opt/clawdbot/bootstrap.sh",
      "sudo chmod +x /opt/clawdbot/bootstrap.sh"
    ]
  }

  # Create systemd service
  provisioner "shell" {
    inline = [
      "sudo tee /etc/systemd/system/clawdbot-agent.service > /dev/null <<EOF",
      "[Unit]",
      "Description=ClawdBot Agent",
      "After=network.target",
      "",
      "[Service]",
      "Type=simple",
      "User=ubuntu",
      "WorkingDirectory=/home/ubuntu/agent",
      "ExecStart=/usr/bin/clawdbot gateway start",
      "Restart=always",
      "RestartSec=10",
      "Environment=NODE_ENV=production",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable clawdbot-agent.service"
    ]
  }

  # Cleanup
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "rm -rf ~/.npm/_cacache"
    ]
  }
}
