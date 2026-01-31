#!/bin/bash
echo ubuntu:TempPass123! | chpasswd
rm -f /etc/systemd/system/ssh.socket.d/override.conf
sed -i 's/^Port 2222/Port 22/' /etc/ssh/sshd_config
systemctl daemon-reload
systemctl restart ssh.socket
systemctl restart ssh
