#!/bin/bash -ex
#
source config.cfg
source admin-openrc
source functions.sh

echocolor "Create DB for SAHARA"
cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE sahara;
GRANT ALL PRIVILEGES ON sahara.* TO 'sahara'@'localhost' IDENTIFIED BY '$SAHARA_DBPASS';
GRANT ALL PRIVILEGES ON sahara.* TO 'sahara'@'%' IDENTIFIED BY '$SAHARA_DBPASS';
FLUSH PRIVILEGES;
EOF
sleep 5

echocolor "Install Python Client"
apt-get -y install python-pip python-sahara sahara-common sahara python-mysqldb python-sqlalchemy
#apt-get install python-pip python-setuptools python-virtualenv python-dev -y

#echocolor "Setting sahara-venv and Pip install sahara"
#virtualenv sahara-venv
##sahara-venv/bin/pip install 'http://tarballs.openstack.org/sahara/sahara-master.tar.gz'
#sahara-venv/bin/pip install sahara
#sahara-venv/bin/pip install 'http://tarballs.openstack.org/sahara/sahara-stable-mitaka.tar.gz'


#echocolor "Install SAHARA SQL Clinet"
#apt-get install libmysqlclient-dev -y
##sahara-venv/bin/pip install mysql-python
#source sahara-venv/bin/activate
#sahara-venv/bin/pip install pymysql
#sahara-venv/bin/pip MySQL-python

mkdir sahara-venv/etc
mkdir /var/log/sahara

echocolor "Configuring SAHARA API"
cp sahara-venv/share/sahara/sahara.conf.sample-basic sahara-venv/etc/sahara.conf
#cp sahara-venv/share/sahara/sahara.conf.sample-basic /etc/sahara/sahara.conf
cp sahara-venv/share/sahara/api-paste.ini sahara-venv/etc/
#cp sahara-venv/share/sahara/policy.json /etc/sahara/

sahara_api_ctl=sahara-venv/etc/sahara.conf
test -f $sahara_api_ctl.orig || cp $sahara_api_ctl $sahara_api_ctl.orig

### Configuring sahara config file sahara-venv/etc/sahara.conf file:
## [DEFAULT] section
ops_edit $sahara_api_ctl DEFAULT use_neutron true
ops_edit $sahara_api_ctl DEFAULT debug true
ops_edit $sahara_api_ctl DEFAULT rpc_backend rabbit
ops_edit $sahara_api_ctl DEFAULT log_dir /var/log/sahara
ops_edit $sahara_api_ctl DEFAULT log_file sahara.log
ops_edit $sahara_api_ctl DEFAULT host $CTL_MGNT_IP
ops_edit $sahara_api_ctl DEFAULT port 8386
ops_edit $sahara_api_ctl DEFAULT os_region_name RegionOne
ops_edit $sahara_api_ctl DEFAULT plugins vanilla,hdp,spark,mapr

## [database] section
ops_edit $sahara_api_ctl database \
    connection mysql+pymysql://sahara:$SAHARA_DBPASS@$CTL_MGNT_IP/sahara

## [keystone_authtoken] section
ops_edit $sahara_api_ctl keystone_authtoken auth_uri http://$CTL_MGNT_IP:5000
ops_edit $sahara_api_ctl keystone_authtoken auth_url http://$CTL_MGNT_IP:35357
ops_edit $sahara_api_ctl keystone_authtoken memcached_servers $CTL_MGNT_IP:11211
ops_edit $sahara_api_ctl keystone_authtoken auth_type password
ops_edit $sahara_api_ctl keystone_authtoken project_domain_name default
ops_edit $sahara_api_ctl keystone_authtoken user_domain_name default
ops_edit $sahara_api_ctl keystone_authtoken project_name service
ops_edit $sahara_api_ctl keystone_authtoken username sahara
ops_edit $sahara_api_ctl keystone_authtoken password $SAHARA_PASS
ops_edit $sahara_api_ctl keystone_authtoken region_name RegionOne


## [oslo_messaging_notifications] section
ops_edit $sahara_api_ctl oslo_messaging_notifications enable true
ops_edit $sahara_api_ctl oslo_messaging_notifications driver messagingv2

## [oslo_messaging_rabbit] section
ops_edit $sahara_api_ctl oslo_messaging_rabbit rabbit_host $CTL_MGNT_IP
ops_edit $sahara_api_ctl oslo_messaging_rabbit rabbit_port 5672
ops_edit $sahara_api_ctl oslo_messaging_rabbit rabbit_hosts $CTL_MGNT_IP:5672
ops_edit $sahara_api_ctl oslo_messaging_rabbit rabbit_userid openstack
ops_edit $sahara_api_ctl oslo_messaging_rabbit rabbit_password $RABBIT_PASS
ops_edit $sahara_api_ctl oslo_messaging_rabbit rabbit_virtual_host /

## [oslo_concurrency] section
ops_edit $sahara_api_ctl oslo_concurrency lock_path /var/oslock/sahara

mkdir -p /var/oslock/sahara
chown -R sahara.sahara /var/oslock/sahara
sleep 5

#echocolor "Configuring MySql my.cnf"
#mysql_cnf=/etc/mysql/my.cnf
#ops_edit $mysql_cnf mysqld max_allowed_packet 256M
##sed -i "s/-l max_allowed_packet      = 16M/-l max_allowed_packet      = 256M/g" /etc/mysql/my.cnf


#echocolor "Restart Mysql database"
#service mysql restart


echocolor "Create the database schema"
sahara-venv/bin/sahara-db-manage --config-file sahara-venv/etc/sahara.conf upgrade head
sleep 3

echocolor "Register SAHARA in the Identity Service Catalog"
openstack user create sahara --domain default --password $SAHARA_PASS
openstack role add --project service --user sahara admin
openstack service create --name sahara --description \
    "Sahara Data Processing" data-processing

openstack endpoint create --region RegionOne data-processing \
    public http://$CTL_MGNT_IP:8386/v1.1/%\(tenant_id\)s
openstack endpoint create --region RegionOne data-processing \
    internal http://$CTL_MGNT_IP:8386/v1.1/%\(tenant_id\)s
openstack endpoint create --region RegionOne data-processing \
    admin http://$CTL_MGNT_IP:8386/v1.1/%\(tenant_id\)s

sleep 3


echocolor "Configuring SAHARA UI & Apache restart"
cd /usr/local/src
git clone https://github.com/openstack/sahara-dashboard
cd /usr/local/src/sahara-dashboard
git checkout stable/mitaka
pip install -e ./
cp /usr/local/src/sahara-dashboard/sahara_dashboard/enabled/* /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/
cd /usr/share/openstack-dashboard/
python manage.py compress --force
python manage.py collectstatic --noinput

service apache2 restart
#systemctl restart httpd

#echocolor "Configuring SAHARA UI & Apache restart"
#pip install sahara-dashboard
#service apache2 restart

echocolor "To Start SAHARA Call"
sahara-venv/bin/sahara-all --config-file sahara-venv/etc/sahara.conf