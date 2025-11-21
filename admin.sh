#!/bin/bash
# Wrapper script to run admin helper on VM
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t vagrant@192.168.121.183 "sudo bash /opt/my-paas/admin_helper.sh"
