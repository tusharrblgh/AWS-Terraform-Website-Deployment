#!/bin/bash
# BY - TUSHAR SRIVASTAVA (Code:ts, ts-2024/31182)

# to save script commands status
FILE1="home/ec2-user/script_status.txt"

# update system
echo -e "System Update Start Successfully\n" >> "$FILE1"
if sudo yum update -y; then
    echo -e "System Updated Sucessfully\n" >> "$FILE1"
else
    echo "Error: Not Update!! Check Command" >> "$FILE1"
fi

# install http
echo -e "http Operation Start Successfully\n" >> "$FILE1"
if sudo yum install httpd -y; then
    echo -e "http Installed Successfully\n" >> "$FILE1"
else
    echo "Error: Not Install!! Check Command" >> "$FILE1"
fi

# start and enable http service
sudo systemctl enable httpd
echo -e "http Enabled Successfully\n" >> "$FILE1"
sudo systemctl start httpd
echo -e "http Started Successfully\n" >> "$FILE1"

# copy content in index.html
echo "The IP is : $(hostname)" > /var/www/html/index.html
echo "index.html File with Content saved in HTML folder Successfully" >> "$FILE1"