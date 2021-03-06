#!/bin/bash -ex
#

source config.cfg
source functions.sh

####################################   
# Ceilomter agent for Compute node #
####################################

echocolor "Installing Ceilomter agent for Compute node"
sleep 3
apt-get -y install ceilometer-agent-compute

echocolor "Backup file config of Ceilomter"
sleep 3
ceilomter_com=/etc/ceilometer/ceilometer.conf
test -f $ceilomter_com.orig || cp $ceilomter_com $ceilomter_com.orig

echo "Edit file ceilometer"
sleep 3

# Edit [DEFAULT] section 

ops_edit $ceilomter_com DEFAULT rpc_backend rabbit
ops_edit $ceilomter_com DEFAULT auth_strategy keystone
ops_edit $ceilomter_com DEFAULT verbose True



# Edit [slo_messaging_rabbit] section 
ops_edit $ceilomter_com oslo_messaging_rabbit rabbit_host $CTL_MGNT_IP
ops_edit $ceilomter_com oslo_messaging_rabbit rabbit_userid openstack
ops_edit $ceilomter_com oslo_messaging_rabbit rabbit_password $RABBIT_PASS

# Edit [keystone_authtoken] section 
ops_edit $ceilomter_com keystone_authtoken auth_uri http://$CTL_MGNT_IP:5000
ops_edit $ceilomter_com keystone_authtoken auth_url http://$CTL_MGNT_IP:35357
ops_edit $ceilomter_com keystone_authtoken auth_type password
ops_edit $ceilomter_com keystone_authtoken project_domain_name default
ops_edit $ceilomter_com keystone_authtoken user_domain_name default
ops_edit $ceilomter_com keystone_authtoken project_name service
ops_edit $ceilomter_com keystone_authtoken username ceilometer
ops_edit $ceilomter_com keystone_authtoken password $CEILOMETER_PASS

# Edit [service_credentials] section 
ops_edit $ceilomter_com service_credentials \
os_auth_url http://$CTL_MGNT_IP:5000/v2.0

ops_edit $ceilomter_com service_credentials os_username ceilometer
ops_edit $ceilomter_com service_credentials os_tenant_name service
ops_edit $ceilomter_com service_credentials os_password $CEILOMETER_PASS
ops_edit $ceilomter_com service_credentials os_endpoint_type internalURL
ops_edit $ceilomter_com service_credentials os_region_name RegionOne	

echo "Edit file /etc/nova/nova.conf on Compute node"
sleep 3

# Edit [DEFAULT] section 
nova_com=/etc/nova/nova.conf
ops_edit $nova_com DEFAULT instance_usage_audit True
ops_edit $nova_com DEFAULT instance_usage_audit_period hour
ops_edit $nova_com DEFAULT notify_on_state_change vm_and_task_state
ops_edit $nova_com DEFAULT notification_driver messagingv2

echo "Restart ceilometer-agent-compute, nova-compute"
sleep 3
service ceilometer-agent-compute restart
service nova-compute restart








