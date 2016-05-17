#!/bin/bash -ex
#

source config.cfg
source functions.sh

echocolor "Create DB for HEAT"
sleep 5
cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE heat;
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$HEAT_DBPASS';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY '$HEAT_DBPASS';
FLUSH PRIVILEGES;
EOF

sleep 5

echocolor "Create user, role and endpoint for HEAT"

openstack user create heat --domain default --password $HEAT_PASS

openstack role add --project service --user heat admin
openstack service create --name heat --description "Orchestration" orchestration
openstack service create --name heat-cfn --description "Orchestration" cloudformation

openstack endpoint create --region RegionOne orchestration public http://$CTL_MGNT_IP:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration internal http://$CTL_MGNT_IP:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration admin http://$CTL_MGNT_IP:8004/v1/%\(tenant_id\)s

openstack endpoint create --region RegionOne cloudformation public http://$CTL_MGNT_IP:8000/v1
openstack endpoint create --region RegionOne cloudformation internal http://$CTL_MGNT_IP:8000/v1
openstack endpoint create --region RegionOne cloudformation admin http://$CTL_MGNT_IP:8000/v1


openstack domain create --description "Stack projects and users" heat
openstack user create --domain heat --password $HEAT_PASS heat_domain_admin
openstack role add --domain heat --user heat_domain_admin admin

openstack role create heat_stack_owner
openstack role add --project demo --user demo heat_stack_owner

openstack role create heat_stack_user

sleep 3

### Install heat packages:
echocolor "Install HEAT Packages"
apt-get install -y heat-api heat-api-cfn heat-engine python-heatclient
sleep 3

echocolor "Configuring HEAT API"
#/* Back-up file heat.conf
heatapi_ctl=/etc/heat/heat.conf
test -f $heatapi_ctl.orig || cp $heatapi_ctl $heatapi_ctl.orig

### Configuring heat config file /etc/heat/heat.conf file:
## [database] section
ops_edit $heatapi_ctl database connection mysql+pymysql://heat:$HEAT_DBPASS@$CTL_MGNT_IP/heat

## [DEFAULT] section
ops_edit $heatapi_ctl DEFAULT rpc_backend rabbit
ops_edit $heatapi_ctl DEFAULT heat_metadata_server_url http://$CTL_MGNT_IP:8000
ops_edit $heatapi_ctl DEFAULT heat_waitcondition_server_url http://$CTL_MGNT_IP/v1/waitcondition
ops_edit $heatapi_ctl DEFAULT stack_domain_admin heat_domain_admin
ops_edit $heatapi_ctl DEFAULT stack_domain_admin_password $HEAT_PASS
ops_edit $heatapi_ctl DEFAULT stack_user_domain_name heat

## [oslo_messaging_rabbit] section
ops_edit $heatapi_ctl oslo_messaging_rabbit rabbit_host $CTL_MGNT_IP
ops_edit $heatapi_ctl oslo_messaging_rabbit rabbit_userid openstack
ops_edit $heatapi_ctl oslo_messaging_rabbit rabbit_password $RABBIT_PASS

## [keystone_authtoken] section
ops_edit $heatapi_ctl keystone_authtoken auth_uri http://$CTL_MGNT_IP:5000
ops_edit $heatapi_ctl keystone_authtoken auth_url http://$CTL_MGNT_IP:35357
ops_edit $heatapi_ctl keystone_authtoken memcached_servers $CTL_MGNT_IP:11211
ops_edit $heatapi_ctl keystone_authtoken auth_type password
ops_edit $heatapi_ctl keystone_authtoken project_domain_name default
ops_edit $heatapi_ctl keystone_authtoken user_domain_name default
ops_edit $heatapi_ctl keystone_authtoken project_name service
ops_edit $heatapi_ctl keystone_authtoken username heat
ops_edit $heatapi_ctl keystone_authtoken password $HEAT_PASS

## [trustee] section
ops_edit $heatapi_ctl trustee auth_type password
ops_edit $heatapi_ctl trustee auth_uri http://$CTL_MGNT_IP:35357
ops_edit $heatapi_ctl trustee username heat
ops_edit $heatapi_ctl trustee password $HEAT_PASS
ops_edit $heatapi_ctl trustee user_domain_name default

## [clients_keystone] section
ops_edit $heatapi_ctl clients_keystone auth_uri http://$CTL_MGNT_IP:35357

## [ec2authtoken] section
ops_edit $heatapi_ctl ec2authtoken auth_uri http://$CTL_MGNT_IP:5000


echocolor "Synchronize DB for HEAT"
### Synchronize your database:
sleep 5
su -s /bin/sh -c "heat-manage db_sync" heat

echocolor "Restart the Orchestration service"
### Restart the Orchestration services:
service heat-api restart
service heat-api-cfn restart
service heat-engine restart

echocolor "Remove HEAT SQLite DB"
### Remove heat SQLite database:
rm -f /var/lib/heat/heat.sqlite

echocolor "Restart Apache2 & memcached"
### Restart Apache2:
service apache2 restart
service memcached restart