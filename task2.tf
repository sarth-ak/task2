provider "aws" {
region = "ap-south-1"
profile= "sarthak"
}

//creating the key
resource "tls_private_key" "this" {
  algorithm = "RSA"
}
module "key_pair"{
  source = "terraform-aws-modules/key-pair/aws"
  key_name   = "mykey5"
  public_key = tls_private_key.this.public_key_openssh
}
data "aws_subnet_ids" "take_id" {
  vpc_id = data.aws_vpc.selected.id
}
//detecting the vpc-id
data "aws_vpc" "selected" {
    default = true
}
//creating and configuring the security group
resource "aws_security_group" "just_testing" {
  name        = "allow"
  description = "Allow TLS inbound traffic"
  vpc_id      =   data.aws_vpc.selected.id
  //rule no 1
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  //rule no 2
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags= {
         Name="trial"
  }
//rule no 3
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  //outbound rule
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

} 
//creating instance
resource "aws_instance" "os_NO_1" {
depend_on=[
aws_security_group.just_testing
]
  ami           = "ami-052c08d70def0ac62"
  instance_type = "t2.micro"
  key_name = "mykey5"
  security_groups = ["allow"]
  tags = {
    Name = "MYOS_TAG"
  }
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.this.private_key_pem
    host     = aws_instance.os_NO_1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
        "sudo yum install httpd -y",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
        "sudo yum install git -y"  
   ]
  }

// now ending the resources aws 
}
//creating the volume
resource "aws_efs_file_system" "efs-example" {
   depends_on=[
aws_instance.os_NO_1
]
   creation_token = "efs-example"
   encrypted = "false"
 tags = {
     Name = "EfsExample"
   }
 }
//creating a mount target
 
resource "aws_efs_mount_target" "beta" {
 depends_on=[
aws_efs_file_system.efs-example,aws_efs_mount_target.gamma
]
  file_system_id = "${aws_efs_file_system.efs-example.id}"
  subnet_id      = "${element(tolist(data.aws_subnet_ids.take_id.ids), 1)}"
  security_groups=[aws_security_group.just_testing.id]
}
resource "aws_efs_mount_target" "gamma" {
 depends_on=[
aws_efs_file_system.efs-example,aws_efs_mount_target.alpha
]
  file_system_id = "${aws_efs_file_system.efs-example.id}"
  subnet_id      = "${element(tolist(data.aws_subnet_ids.take_id.ids), 2)}"
   security_groups=[aws_security_group.just_testing.id]
}

resource "aws_efs_mount_target" "alpha" {
 depends_on=[
aws_efs_file_system.efs-example
]
  file_system_id = "${aws_efs_file_system.efs-example.id}"
  subnet_id      = "${element(tolist(data.aws_subnet_ids.take_id.ids), 0)}"
  security_groups=[aws_security_group.just_testing.id]
}
resource "null_resource" "mounting" {
depends_on=[
aws_efs_mount_target.beta,aws_efs_file_system.efs-example
]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.this.private_key_pem
    host     = aws_instance.os_NO_1.public_ip
  }
  provisioner "remote-exec" {
        inline  = [
      "sudo rm -rf /var/www/html/*",
      
/*
      mount the efs volume
      "sudo mount  ${aws_efs_file_system.efs-example.dns_name} /var/www/html",
       create fstab entry to ensure automount on reboots
       https://docs.aws.amazon.com/efs/latest/ug/mount-fs-auto-mount-onreboot.html#mount-fs-auto-mount-on-creation
      "sudo su -c \"echo '${aws_efs_file_system.efs-example.dns_name}: /var/www/html efs defaults, _netdev 0 0 ' >> sudo /etc/fstab\"",
      " sudo git clone https://github.com/sart-ak/task_trail.git /var/www/html "
 */
"sudo echo ${aws_efs_file_system.efs-example.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
"sudo mount  ${aws_efs_file_system.efs-example.dns_name}:/  /var/www/html", 
" sudo git clone https://github.com/sart-ak/task_trail.git /var/www/html "  
 ]
    }
  
}
//creating a bucket 
resource "aws_s3_bucket" "b" {
 depends_on=[
aws_efs_file_system.efs-example
]
  bucket = "my-tf-test-bucket09"
  acl    = "public-read"
  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
  provisioner "local-exec" {
        command = "git clone https://github.com/sarth-ak/images.git web_file "
    }
}
  
//uploading images in bucket from github to base (local os) and local os to s3 bucket 
resource "aws_s3_bucket_object" "object" {
  depends_on=[
    aws_s3_bucket.b
]
  bucket = "my-tf-test-bucket09"
  key    = "traial.jpeg"
  acl     = "public-read"
  content_type = "image/jpeg"
  source = "C:/Users/Asus/Desktop/Terraform/test2/web_file/traial.jpeg" 
}
//deleting file before everything it runs at last automatically 
resource "null_resource" "remove_files_left" {
 provisioner "local-exec" {
       when    = destroy
       command = "rd /S/Q web_file"
    }
}
//NOW setting up cloudfront 
resource "aws_cloudfront_distribution" "s3_distribution" {
    depends_on=[
  aws_s3_bucket_object.object,null_resource.mounting
]
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = "S3-${aws_s3_bucket.b.bucket}"
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "redirect-to-https"
    }
	enabled             = true
    origin {
        domain_name = aws_s3_bucket.b.bucket_domain_name
        origin_id   = "S3-${aws_s3_bucket.b.bucket}"
    }
    restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }
    viewer_certificate {
        cloudfront_default_certificate = true
    }
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.this.private_key_pem
    host     = aws_instance.os_NO_1.public_ip
  }
provisioner "remote-exec" {
        inline  = [
            "sudo su << EOF",
            "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.object.key}'>\" >> /var/www/html/test.html",
            "EOF"
        ]
    }

}
// now running it in local browser
resource "null_resource" "local_browser" {
depends_on=[
aws_cloudfront_distribution.s3_distribution,aws_s3_bucket_object.object,null_resource.mounting
]

triggers={
always_run = "${timestamp()}"
}
 provisioner "local-exec" {
       
        command = "start chrome http://${aws_instance.os_NO_1.public_ip}/test.html"
    }
}
output "try_using_this_ip_with_testhtml"{ 
value= "${aws_instance.os_NO_1.public_ip}"
}
